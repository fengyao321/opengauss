#include "postgres.h"
#include "knl/knl_instance.h"

extern "C" void _PG_init(void);
extern "C" void _PG_fini(void);
extern "C" void init_session_vars(void);
extern "C" void set_extension_index(uint32 index);
extern "C" Datum fetch_status(PG_FUNCTION_ARGS);
extern "C" Datum rowcount(PG_FUNCTION_ARGS);
extern "C" Datum rowcount_big(PG_FUNCTION_ARGS);
extern "C" Datum procid(PG_FUNCTION_ARGS);
extern "C" Datum sql_variantin(PG_FUNCTION_ARGS);
extern "C" Datum sql_variantout(PG_FUNCTION_ARGS);
extern "C" Datum sql_variantrecv(PG_FUNCTION_ARGS);
extern "C" Datum sql_variantsend(PG_FUNCTION_ARGS);
extern "C" Datum databasepropertyex(PG_FUNCTION_ARGS);
extern "C" Datum suser_name(PG_FUNCTION_ARGS);
extern "C" Datum suser_id(PG_FUNCTION_ARGS);
extern "C" Datum get_scope_identity(PG_FUNCTION_ARGS);
extern "C" Datum get_ident_current(PG_FUNCTION_ARGS);
extern "C" Datum numeric_log10(PG_FUNCTION_ARGS);
extern "C" Datum shark_timestamp_diff(PG_FUNCTION_ARGS);
extern "C" Datum shark_timestamp_diff_big(PG_FUNCTION_ARGS);
static void fetch_cursor_end_hook(int fetch_status);
static void rowcount_hook(int64 rowcount);
extern void set_procid(Oid oid);
extern Oid get_procid();
extern int PltsqlNewScopeIdentityNestLevel();
extern void PltsqlRevertLastScopeIdentity(int nestLevel);
extern int128 last_scope_identity_value();
extern char* GetPhysicalSchemaName(char *dbName, const char *schemaName);
extern void AssignIdentitycmdsHook(void);
extern void InitIntervalLookup(void);

typedef struct SeqTableIdentityData {
    Oid relid;                /* pg_class OID of this sequence */
    bool lastIdentityValid; /* check value validity */
    int128 lastIdentity;     /* sequence identity value */
} SeqTableIdentityData;

typedef struct ScopeIdentityStack {
    struct ScopeIdentityStack* prev;                      /* previous stack item if any */
    int nestLevel;                                       /* nesting depth at which we made entry */
    SeqTableIdentityData last_used_seq_identity_in_scope; /* current scope identity value */
} ScopeIdentityStack;
typedef struct SharkContext {
    bool dialect_sql;
    int fetch_status;
    int64 rowcount;
    Oid procid;
    ScopeIdentityStack *lastUsedScopeSeqIdentity;
    int pltsqlScopeIdentityNestLevel;
    Oid varbinaryOid; /* oid of sys.varbinary */
} sharkContext;

SharkContext* GetSessionContext();

typedef enum {
    FETCH_STATUS_SUCCESS = 0,    // The FETCH statement was successful.
    FETCH_STATUS_FAIL = -1,      // The FETCH statement failed or the row was beyond the result set.
    FETCH_STATUS_NOT_EXIST = -2, // The row fetched is missing.
    FETCH_STATUS_NOT_FETCH = -9  // The cursor is not performing a fetch operation.
} CursorFetchStatus;

typedef struct InnerSQLInfo {
    char* sql;
    int sql_length;    /* size of string */
} InnerSQLInfo;

#define INNER_SQL_NUMBER 14

static InnerSQLInfo g_inner_sqls[INNER_SQL_NUMBER] = {
        {"SET extra_float_digits = 3", 26},
        {"set client_encoding = 'UTF8'", 28},
        {"SET application_name = 'PostgreSQL JDBC Driver'", 47},
        {"select version()", 16},
        {"select datcompatibility from pg_database where datname=", 55},
        {"set dolphin.b_compatibility_mode to on", 38},
        {"SELECT t.oid, t.typname FROM pg_catalog.pg_type t  where t.typname = 'year' or t.typname = 'uint1' or"
         " t.typname = 'uint2' or t.typname = 'uint4' or t.typname = 'uint8' or t.typname = '_uint1' or t.typname"
         " = '_uint2' or t.typname = '_uint4' or t.typname = '_uint8'", 263},
        {"select count(1) from pg_extension where extname = 'dolphin'", 50},
        {"show dolphin.b_compatibility_mode", 59},
        {"select name, setting from pg_settings where name in ('connection_info')", 71},
        {"select name, setting from pg_settings where name in ($1)", 56},
        {"set connection_info = '{\"driver_name\":\"JDBC\",\"driver_version\":", 62},
        {"select count(*) from pg_settings where name = 'support_batch_bind' and setting = 'on'", 85},
        {"SELECT c.oid, a.attnum, a.attname, c.relname, n.nspname, a.attnotnull OR (t.typtype = 'd' AND "
         "t.typnotnull), pg_catalog.pg_get_expr(d.adbin, d.adrelid) LIKE '%nextval(%' FROM pg_catalog.pg_class "
         "c JOIN pg_catalog.pg_namespace n ON (c.relnamespace = n.oid) JOIN pg_catalog.pg_attribute a "
         "ON (c.oid = a.attrelid) JOIN pg_catalog.pg_type t ON (a.atttypid = t.oid) LEFT JOIN pg_catalog.pg_attrdef d",
         294}
    };

