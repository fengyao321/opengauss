/*-------------------------------------------------------------------------
 *
 * jsonpath.h
 *    Definitions for jsonpath datatype
 *
 * Copyright (c) Huawei Technologies Co., Ltd. 2012-2018. All rights reserved.
 * Copyright (c) 2019-2024, PostgreSQL Global Development Group
 *
 * IDENTIFICATION
 *    src/include/utils/jsonpath.h
 *
 *-------------------------------------------------------------------------
 */

#ifndef JSONPATH_H
#define JSONPATH_H

#include "fmgr.h"
#include "nodes/pg_list.h"
#include "nodes/primnodes.h"
#include "utils/jsonb.h"

/* jsonpath .y 和.l 中使用 BEGIN */
#define YY_NO_UNISTD_H
union YYSTYPE;
/* jsonpath .y 和.l 中使用 END */

typedef struct {
    int32        vl_len_;        /* varlena header (do not touch directly!) */
    uint32        header;            /* version and flags (see below) */
    char        data[FLEXIBLE_ARRAY_MEMBER];
} JsonPath;

#define JSONPATH_VERSION    (0x01)
#define JSONPATH_LAX        (0x80000000)
#define JSONPATH_HDRSZ        (offsetof(JsonPath, data))

#define PG_GETARG_JSONPATH_P(x)            DatumGetJsonPathP(PG_GETARG_DATUM(x))
#define PG_GETARG_JSONPATH_P_COPY(x)    DatumGetJsonPathPCopy(PG_GETARG_DATUM(x))
#define PG_RETURN_JSONPATH_P(p)            PG_RETURN_POINTER(p)

/*
 * All node's type of jsonpath expression
 *
 * These become part of the on-disk representation of the jsonpath type.
 * Therefore, to preserve pg_upgradability, the order must not be changed, and
 * new values must be added at the end.
 *
 * It is recommended that switch cases etc. in other parts of the code also
 * use this order, to maintain some consistency.
 */
typedef enum JsonPathItemType {
    JPI_NULL = jbvNull,            /* NULL literal */
    JPI_STRING = jbvString,        /* string literal */
    JPI_NUMERIC = jbvNumeric,    /* numeric literal */
    JPI_BOOL = jbvBool,            /* boolean literal: TRUE or FALSE */
    JPI_AND,                        /* predicate && predicate */
    JPI_OR,                        /* predicate || predicate */
    JPI_NOT,                        /* ! predicate */
    JPI_IS_UNKNOWN,                /* (predicate) IS UNKNOWN */
    JPI_EQUAL,                    /* expr == expr */
    JPI_NOT_EQUAL,                /* expr != expr */
    JPI_LESS,                    /* expr < expr */
    JPI_GREATER,                    /* expr > expr */
    JPI_LESS_OR_EQUAL,                /* expr <= expr */
    JPI_GREATER_OR_EQUAL,            /* expr >= expr */
    JPI_ADD,                        /* expr + expr */
    JPI_SUB,                        /* expr - expr */
    JPI_MUL,                        /* expr * expr */
    JPI_DIV,                        /* expr / expr */
    JPI_MOD,                        /* expr % expr */
    JPI_PLUS,                       /* + expr */
    JPI_MINUS,                      /* - expr */
    JPI_ANY_ARRAY,                /* [*] */
    JPI_ANY_KEY,                    /* .* */
    JPI_INDEX_ARRAY,                /* [subscript, ...] */
    JPI_ANY,                        /* .** */
    JPI_KEY,                        /* .key */
    JPI_CURRENT,                    /* @ */
    JPI_ROOT,                    /* $ */
    JPI_VARIABLE,                /* $variable */
    JPI_FILTER,                    /* ? (predicate) */
    JPI_EXISTS,                    /* EXISTS (expr) predicate */
    JPI_TYPE,                    /* .type() item method */
    JPI_SIZE,                    /* .size() item method */
    JPI_ABS,                        /* .abs() item method */
    JPI_FLOOR,                    /* .floor() item method */
    JPI_CEILING,                    /* .ceiling() item method */
    JPI_KEYVALUE,                /* .keyvalue() item method */
    JPI_SUBSCRIPT,                /* array subscript: 'expr' or 'expr TO expr' */
    JPI_LAST,                    /* LAST array subscript */
    JPI_STARTS_WITH,                /* STARTS WITH predicate */
    JPI_LIKE_REGEX,                /* LIKE_REGEX predicate */
    JPI_BIGINT,                    /* .bigint() item method */
    JPI_BOOLEAN,                    /* .boolean() item method */
    JPI_INTEGER,                    /* .integer() item method */
    JPI_DOUBLE,                    /* .double() item method */
    JPI_DATETIME,                /* .datetime() item method */
    JPI_DATE,                    /* .date() item method */
    JPI_DECIMAL,                    /* .decimal() item method */
    JPI_NUMBER,                    /* .number() item method */
    JPI_STRING_FUNC,                /* .string() item method */
    JPI_TIME,                    /* .time() item method */
    JPI_TIME_TZ,                    /* .time_tz() item method */
    JPI_TIMESTAMP,                /* .timestamp() item method */
    JPI_TIMESTAMP_TZ,                /* .timestamp_tz() item method */
} JsonPathItemType;

/*
 * JsonWrapper -
 *        representation of WRAPPER clause for JSON_QUERY()
 */
typedef enum JsonWrapper {
    JSW_UNSPEC,
    JSW_NONE,
    JSW_CONDITIONAL,
    JSW_UNCONDITIONAL,
} JsonWrapper;

/* XQuery regex mode flags for LIKE_REGEX predicate */
#define JSP_REGEX_ICASE        0x01    /* i flag, case insensitive */
#define JSP_REGEX_DOTALL    0x02    /* s flag, dot matches newline */
#define JSP_REGEX_MLINE        0x04    /* m flag, ^/$ match at newlines */
#define JSP_REGEX_WSPACE    0x08    /* x flag, ignore whitespace in pattern */
#define JSP_REGEX_QUOTE        0x10    /* q flag, no special characters */

/*
 * Support functions to parse/construct binary value.
 * Unlike many other representation of expression the first/main
 * node is not an operation but left operand of expression. That
 * allows to implement cheap follow-path descending in jsonb
 * structure and then execute operator with right operand
 */

typedef struct JsonPathItem {
    JsonPathItemType type;

    /* position form base to next node */
    int32 nextPos;

    /*
     * pointer into JsonPath value to current node, all positions of current
     * are relative to this base
     */
    char *base;

    union JsonPathContent {
        /* classic operator with two operands: and, or etc */
        struct {
            int32 left;
            int32 right;
        } args;

        /* any unary operation */
        int32 arg;
        /* storage for JPI_INDEX_ARRAY: indexes of array */
        struct IndexArray {
            int32 nelems;
            struct ArrayIndexRange {
                int32 from;
                int32 to;
            } *elems;
        } array;

        /* jpiAny: levels */
        struct {
            uint32 first;
            uint32 last;
        } anybounds;

        struct {
            int32 expr;
            char *pattern;
            int32 patternlen;
            uint32 flags;
        } like_regex;

        struct {
            char *data;    /* for bool, numeric and string/key */
            int32 datalen;    /* filled only for string/key */
        } value;
    } content;
} JsonPathItem;

extern void JspInit(JsonPathItem *v, JsonPath *js);
extern void jspInitByBuffer(JsonPathItem *v, char *base, int32 pos);
extern bool jspGetNext(JsonPathItem *v, JsonPathItem *a);
extern Numeric jspGetNumeric(JsonPathItem *v);
extern bool jspGetBool(JsonPathItem *v);
extern char *jspGetString(JsonPathItem *v, int32 *len);
extern bool jspGetArraySubscript(JsonPathItem *v, JsonPathItem *from,
                                 JsonPathItem *to, int i);
extern void JspGetArg(JsonPathItem *v, JsonPathItem *a);
extern void JspGetLeftArg(JsonPathItem *v, JsonPathItem *a);
extern void JspGetRightArg(JsonPathItem *v, JsonPathItem *a);
extern JsonPath* CstringToJsonpath(char* s);
extern bool jspHasNext(JsonPathItem* jsp);
extern bool jspIsScalar(JsonPathItemType type);
extern const char *JspOperationName(JsonPathItemType type);

extern Datum jsonpath_in(PG_FUNCTION_ARGS);
extern Datum jsonpath_recv(PG_FUNCTION_ARGS);
extern Datum jsonpath_out(PG_FUNCTION_ARGS);
extern Datum jsonpath_send(PG_FUNCTION_ARGS);

extern JsonPath* DatumGetJsonPathP(Datum d);
extern JsonPath* DatumGetJsonPathPCopy(Datum d);
/*
 * Parsing support data structures.
 */

typedef struct JsonPathParseItem JsonPathParseItem;

struct ArrayIndexRange {
    JsonPathParseItem *from;
    JsonPathParseItem *to;
};

struct JsonPathParseItem {
    JsonPathItemType type;
    JsonPathParseItem *next;    /* next in path */

    union {
        /* classic operator with two operands: and, or etc */
        struct {
            JsonPathParseItem *left;
            JsonPathParseItem *right;
        } args;

        /* any unary operation */
        JsonPathParseItem *arg;

        /* storage for JPI_INDEX_ARRAY: indexes of array */
        struct {
            int             nelems;
            ArrayIndexRange *elems;
        } array;

        /* jpiAny: levels */
        struct {
            uint32 first;
            uint32 last;
        } anybounds;

        struct {
            JsonPathParseItem *expr;
            char *pattern;    /* could not be not null-terminated */
            uint32 patternlen;
            uint32 flags;
        } like_regex;

        /* scalars */
        Numeric numeric;
        bool boolean;
        struct {
            uint32 len;
            char *val;    /* could not be not null-terminated */
        } string;
    } value;
};

typedef struct JsonPathParseResult {
    JsonPathParseItem *expr;
    bool lax;
} JsonPathParseResult;

extern JsonPathParseResult *ParseJsonPath(const char *str, int len,
                                          struct Node *escontext);
extern bool JspConvertRegexFlags(uint32 xflags, int *result);

typedef struct JsonPathString {
    char *val;
    int len;
    int total;
} JsonPathString;

#endif
