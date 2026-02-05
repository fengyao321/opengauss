/* -------------------------------------------------------------------------
 *
 * pgstat_shmem.cpp
 *
 * Shared-memory pgstat storage and helpers.
 *
 * -------------------------------------------------------------------------
 */
#include "postgres.h"
#include "knl/knl_variable.h"

#include "pgstat_shmem.h"
#include "storage/shmem.h"
#include "utils/dynahash.h"
#include "utils/hsearch.h"
#include "utils/memutils.h"
#include "access/hash.h"

PgStatSharedState* g_pgstat_shared = NULL;

#define PGSTAT_SHMEM_DB_HASH_SIZE 256
#define PGSTAT_SHMEM_TAB_HASH_SIZE 65536
#define PGSTAT_SHMEM_FUNC_HASH_SIZE 8192

#define PGSTAT_SNAPSHOT_DB_HASH_SIZE 16
#define PGSTAT_SNAPSHOT_TAB_HASH_SIZE 512
#define PGSTAT_SNAPSHOT_FUNC_HASH_SIZE 512

static inline uint32 pgstat_hash_dbid(Oid dbid)
{
    return hash_uint32((uint32)dbid);
}

static inline uint32 pgstat_hash_tabkey(const PgStatSharedTabKey* key)
{
    return tag_hash((const void*)key, sizeof(PgStatSharedTabKey));
}

static inline uint32 pgstat_hash_funckey(const PgStatSharedFuncKey* key)
{
    return tag_hash((const void*)key, sizeof(PgStatSharedFuncKey));
}

static inline LWLock* pgstat_db_lock(Oid dbid)
{
    uint32 hash = pgstat_hash_dbid(dbid);
    return &g_pgstat_shared->db_locks[hash % PGSTAT_DB_NPARTITIONS].lock;
}

static inline LWLock* pgstat_tab_lock(const PgStatSharedTabKey* key)
{
    uint32 hash = pgstat_hash_tabkey(key);
    return &g_pgstat_shared->tab_locks[hash % PGSTAT_TAB_NPARTITIONS].lock;
}

static inline LWLock* pgstat_func_lock(const PgStatSharedFuncKey* key)
{
    uint32 hash = pgstat_hash_funckey(key);
    return &g_pgstat_shared->func_locks[hash % PGSTAT_FUNC_NPARTITIONS].lock;
}

static void pgstat_lock_all(LWLockPadded* locks, int count, LWLockMode mode)
{
    for (int i = 0; i < count; i++)
        LWLockAcquire(&locks[i].lock, mode);
}

static void pgstat_unlock_all(LWLockPadded* locks, int count)
{
    for (int i = count - 1; i >= 0; i--)
        LWLockRelease(&locks[i].lock);
}

static inline bool pgstat_dbid_visible(Oid dbid, Oid onlydb)
{
    if (onlydb == InvalidOid)
        return true;
    return (dbid == onlydb || dbid == InvalidOid);
}

static void pgstat_shared_init_db_entry(PgStatSharedDBEntry* entry, Oid dbid)
{
    errno_t rc = memset_s(entry, sizeof(PgStatSharedDBEntry), 0, sizeof(PgStatSharedDBEntry));
    securec_check(rc, "\0", "\0");
    entry->databaseid = dbid;
    entry->stat_reset_timestamp = GetCurrentTimestamp();
}

static void pgstat_shared_init_tab_entry(PgStatSharedTabEntry* entry, const PgStatSharedTabKey* key)
{
    errno_t rc = memset_s(entry, sizeof(PgStatSharedTabEntry), 0, sizeof(PgStatSharedTabEntry));
    securec_check(rc, "\0", "\0");
    entry->key = *key;
}

static void pgstat_shared_init_func_entry(PgStatSharedFuncEntry* entry, const PgStatSharedFuncKey* key)
{
    errno_t rc = memset_s(entry, sizeof(PgStatSharedFuncEntry), 0, sizeof(PgStatSharedFuncEntry));
    securec_check(rc, "\0", "\0");
    entry->key = *key;
}

Size PgStatShmemSize(void)
{
    Size size = MAXALIGN(sizeof(PgStatSharedState));
    size = add_size(size, hash_estimate_size(PGSTAT_SHMEM_DB_HASH_SIZE, sizeof(PgStatSharedDBEntry)));
    size = add_size(size, hash_estimate_size(PGSTAT_SHMEM_TAB_HASH_SIZE, sizeof(PgStatSharedTabEntry)));
    size = add_size(size, hash_estimate_size(PGSTAT_SHMEM_FUNC_HASH_SIZE, sizeof(PgStatSharedFuncEntry)));
    return size;
}

void PgStatShmemInit(void)
{
    bool found = false;
    HASHCTL ctl;
    errno_t rc;

    g_pgstat_shared = (PgStatSharedState*)ShmemInitStruct("PgStat Shared State", sizeof(PgStatSharedState), &found);

    if (found)
        return;

    for (int i = 0; i < PGSTAT_DB_NPARTITIONS; i++)
        LWLockInitialize(&g_pgstat_shared->db_locks[i].lock, LWTRANCHE_PGSTAT_HASH);
    for (int i = 0; i < PGSTAT_TAB_NPARTITIONS; i++)
        LWLockInitialize(&g_pgstat_shared->tab_locks[i].lock, LWTRANCHE_PGSTAT_HASH);
    for (int i = 0; i < PGSTAT_FUNC_NPARTITIONS; i++)
        LWLockInitialize(&g_pgstat_shared->func_locks[i].lock, LWTRANCHE_PGSTAT_HASH);
    LWLockInitialize(&g_pgstat_shared->global_lock.lock, LWTRANCHE_PGSTAT_HASH);

    rc = memset_s(&ctl, sizeof(ctl), 0, sizeof(ctl));
    securec_check(rc, "\0", "\0");
    ctl.keysize = sizeof(Oid);
    ctl.entrysize = sizeof(PgStatSharedDBEntry);
    ctl.hash = oid_hash;
    g_pgstat_shared->db_hash = ShmemInitHash("PgStat DB Hash", PGSTAT_SHMEM_DB_HASH_SIZE,
        PGSTAT_SHMEM_DB_HASH_SIZE, &ctl, HASH_ELEM | HASH_FUNCTION);

    rc = memset_s(&ctl, sizeof(ctl), 0, sizeof(ctl));
    securec_check(rc, "\0", "\0");
    ctl.keysize = sizeof(PgStatSharedTabKey);
    ctl.entrysize = sizeof(PgStatSharedTabEntry);
    ctl.hash = tag_hash;
    g_pgstat_shared->tab_hash = ShmemInitHash("PgStat TAB Hash", PGSTAT_SHMEM_TAB_HASH_SIZE,
        PGSTAT_SHMEM_TAB_HASH_SIZE, &ctl, HASH_ELEM | HASH_FUNCTION);

    rc = memset_s(&ctl, sizeof(ctl), 0, sizeof(ctl));
    securec_check(rc, "\0", "\0");
    ctl.keysize = sizeof(PgStatSharedFuncKey);
    ctl.entrysize = sizeof(PgStatSharedFuncEntry);
    ctl.hash = tag_hash;
    g_pgstat_shared->func_hash = ShmemInitHash("PgStat FUNC Hash", PGSTAT_SHMEM_FUNC_HASH_SIZE,
        PGSTAT_SHMEM_FUNC_HASH_SIZE, &ctl, HASH_ELEM | HASH_FUNCTION);

    rc = memset_s(&g_pgstat_shared->global_stats, sizeof(PgStat_GlobalStats), 0, sizeof(PgStat_GlobalStats));
    securec_check(rc, "\0", "\0");
    g_pgstat_shared->global_stats.stat_reset_timestamp = GetCurrentTimestamp();
}

PgStatSharedDBEntry* pgstat_shared_get_db_entry(Oid dbid, bool create, LWLockMode mode, LWLock** lock, bool* found)
{
    if (g_pgstat_shared == NULL)
        return NULL;

    LWLock* l = pgstat_db_lock(dbid);
    LWLockAcquire(l, mode);

    HASHACTION action = create ? HASH_ENTER : HASH_FIND;
    bool local_found = false;
    PgStatSharedDBEntry* entry =
        (PgStatSharedDBEntry*)hash_search(g_pgstat_shared->db_hash, &dbid, action, &local_found);

    if (entry == NULL) {
        LWLockRelease(l);
        if (lock)
            *lock = NULL;
        if (found)
            *found = false;
        return NULL;
    }

    if (!local_found && create)
        pgstat_shared_init_db_entry(entry, dbid);

    if (found)
        *found = local_found;
    if (lock)
        *lock = l;
    return entry;
}

PgStatSharedTabEntry* pgstat_shared_get_tab_entry(Oid dbid, Oid relid, uint32 statFlag, bool create, LWLockMode mode,
    LWLock** lock, bool* found)
{
    if (g_pgstat_shared == NULL)
        return NULL;

    PgStatSharedTabKey key;
    key.databaseid = dbid;
    key.tableid = relid;
    key.statFlag = statFlag;

    LWLock* l = pgstat_tab_lock(&key);
    LWLockAcquire(l, mode);

    HASHACTION action = create ? HASH_ENTER : HASH_FIND;
    bool local_found = false;
    PgStatSharedTabEntry* entry =
        (PgStatSharedTabEntry*)hash_search(g_pgstat_shared->tab_hash, &key, action, &local_found);

    if (entry == NULL) {
        LWLockRelease(l);
        if (lock)
            *lock = NULL;
        if (found)
            *found = false;
        return NULL;
    }

    if (!local_found && create)
        pgstat_shared_init_tab_entry(entry, &key);

    if (found)
        *found = local_found;
    if (lock)
        *lock = l;
    return entry;
}

PgStatSharedFuncEntry* pgstat_shared_get_func_entry(Oid dbid, Oid funcid, bool create, LWLockMode mode, LWLock** lock,
    bool* found)
{
    if (g_pgstat_shared == NULL)
        return NULL;

    PgStatSharedFuncKey key;
    key.databaseid = dbid;
    key.functionid = funcid;

    LWLock* l = pgstat_func_lock(&key);
    LWLockAcquire(l, mode);

    HASHACTION action = create ? HASH_ENTER : HASH_FIND;
    bool local_found = false;
    PgStatSharedFuncEntry* entry =
        (PgStatSharedFuncEntry*)hash_search(g_pgstat_shared->func_hash, &key, action, &local_found);

    if (entry == NULL) {
        LWLockRelease(l);
        if (lock)
            *lock = NULL;
        if (found)
            *found = false;
        return NULL;
    }

    if (!local_found && create)
        pgstat_shared_init_func_entry(entry, &key);

    if (found)
        *found = local_found;
    if (lock)
        *lock = l;
    return entry;
}

void pgstat_shared_release_lock(LWLock* lock)
{
    if (lock != NULL)
        LWLockRelease(lock);
}

bool pgstat_shared_remove_tab_entry(Oid dbid, Oid relid, uint32 statFlag, PgStatSharedTabEntry* removed)
{
    if (g_pgstat_shared == NULL)
        return false;

    PgStatSharedTabKey key;
    key.databaseid = dbid;
    key.tableid = relid;
    key.statFlag = statFlag;

    LWLock* l = pgstat_tab_lock(&key);
    LWLockAcquire(l, LW_EXCLUSIVE);

    PgStatSharedTabEntry* entry = (PgStatSharedTabEntry*)hash_search(g_pgstat_shared->tab_hash, &key, HASH_FIND, NULL);
    if (entry == NULL) {
        LWLockRelease(l);
        return false;
    }

    if (removed != NULL) {
        errno_t rc = memcpy_s(removed, sizeof(PgStatSharedTabEntry), entry, sizeof(PgStatSharedTabEntry));
        securec_check(rc, "\0", "\0");
    }

    (void)hash_search(g_pgstat_shared->tab_hash, &key, HASH_REMOVE, NULL);
    LWLockRelease(l);
    return true;
}

bool pgstat_shared_remove_func_entry(Oid dbid, Oid funcid)
{
    if (g_pgstat_shared == NULL)
        return false;

    PgStatSharedFuncKey key;
    key.databaseid = dbid;
    key.functionid = funcid;

    LWLock* l = pgstat_func_lock(&key);
    LWLockAcquire(l, LW_EXCLUSIVE);

    PgStatSharedFuncEntry* entry =
        (PgStatSharedFuncEntry*)hash_search(g_pgstat_shared->func_hash, &key, HASH_FIND, NULL);
    if (entry == NULL) {
        LWLockRelease(l);
        return false;
    }

    (void)hash_search(g_pgstat_shared->func_hash, &key, HASH_REMOVE, NULL);
    LWLockRelease(l);
    return true;
}

static void pgstat_shared_remove_tab_by_dbid(Oid dbid)
{
    if (g_pgstat_shared == NULL)
        return;

    pgstat_lock_all(g_pgstat_shared->tab_locks, PGSTAT_TAB_NPARTITIONS, LW_EXCLUSIVE);

    HASH_SEQ_STATUS seq;
    hash_seq_init(&seq, g_pgstat_shared->tab_hash);
    for (;;) {
        PgStatSharedTabEntry* entry = (PgStatSharedTabEntry*)hash_seq_search(&seq);
        if (entry == NULL)
            break;
        if (entry->key.databaseid != dbid)
            continue;
        PgStatSharedTabKey key = entry->key;
        (void)hash_search(g_pgstat_shared->tab_hash, &key, HASH_REMOVE, NULL);
    }

    pgstat_unlock_all(g_pgstat_shared->tab_locks, PGSTAT_TAB_NPARTITIONS);
}

static void pgstat_shared_remove_func_by_dbid(Oid dbid)
{
    if (g_pgstat_shared == NULL)
        return;

    pgstat_lock_all(g_pgstat_shared->func_locks, PGSTAT_FUNC_NPARTITIONS, LW_EXCLUSIVE);

    HASH_SEQ_STATUS seq;
    hash_seq_init(&seq, g_pgstat_shared->func_hash);
    for (;;) {
        PgStatSharedFuncEntry* entry = (PgStatSharedFuncEntry*)hash_seq_search(&seq);
        if (entry == NULL)
            break;
        if (entry->key.databaseid != dbid)
            continue;
        PgStatSharedFuncKey key = entry->key;
        (void)hash_search(g_pgstat_shared->func_hash, &key, HASH_REMOVE, NULL);
    }

    pgstat_unlock_all(g_pgstat_shared->func_locks, PGSTAT_FUNC_NPARTITIONS);
}

void pgstat_shared_reset_db(Oid dbid)
{
    LWLock* lock = NULL;
    PgStatSharedDBEntry* dbentry = pgstat_shared_get_db_entry(dbid, false, LW_EXCLUSIVE, &lock, NULL);
    if (dbentry != NULL) {
        dbentry->n_xact_commit = 0;
        dbentry->n_xact_rollback = 0;
        dbentry->n_blocks_fetched = 0;
        dbentry->n_blocks_hit = 0;
        dbentry->n_cu_mem_hit = 0;
        dbentry->n_cu_hdd_sync = 0;
        dbentry->n_cu_hdd_asyn = 0;
        dbentry->n_tuples_returned = 0;
        dbentry->n_tuples_fetched = 0;
        dbentry->n_tuples_inserted = 0;
        dbentry->n_tuples_updated = 0;
        dbentry->n_tuples_deleted = 0;
        dbentry->last_autovac_time = 0;
        dbentry->n_conflict_tablespace = 0;
        dbentry->n_conflict_lock = 0;
        dbentry->n_conflict_snapshot = 0;
        dbentry->n_conflict_bufferpin = 0;
        dbentry->n_conflict_startup_deadlock = 0;
        dbentry->n_temp_bytes = 0;
        dbentry->n_temp_files = 0;
        dbentry->n_deadlocks = 0;
        dbentry->n_block_read_time = 0;
        dbentry->n_block_write_time = 0;
        dbentry->n_mem_mbytes_reserved = 0;
        dbentry->stat_reset_timestamp = GetCurrentTimestamp();
        pgstat_shared_release_lock(lock);
    }

    pgstat_shared_remove_tab_by_dbid(dbid);
    pgstat_shared_remove_func_by_dbid(dbid);
}

void pgstat_shared_reset_sharedcounter(PgStat_Shared_Reset_Target target)
{
    if (g_pgstat_shared == NULL)
        return;

    if (target != RESET_BGWRITER)
        return;

    LWLock* lock = pgstat_shared_global_lock();
    if (lock == NULL)
        return;

    LWLockAcquire(lock, LW_EXCLUSIVE);
    errno_t rc = memset_s(&g_pgstat_shared->global_stats, sizeof(PgStat_GlobalStats), 0, sizeof(PgStat_GlobalStats));
    securec_check(rc, "\0", "\0");
    g_pgstat_shared->global_stats.stat_reset_timestamp = GetCurrentTimestamp();
    LWLockRelease(lock);
}

void pgstat_shared_drop_db(Oid dbid)
{
    LWLock* lock = NULL;
    PgStatSharedDBEntry* dbentry = pgstat_shared_get_db_entry(dbid, false, LW_EXCLUSIVE, &lock, NULL);
    if (dbentry != NULL) {
        (void)hash_search(g_pgstat_shared->db_hash, &dbid, HASH_REMOVE, NULL);
        pgstat_shared_release_lock(lock);
    }

    pgstat_shared_remove_tab_by_dbid(dbid);
    pgstat_shared_remove_func_by_dbid(dbid);
}

static PgStat_StatDBEntry* snapshot_get_db_entry(HTAB* dbhash, MemoryContext mcxt, Oid dbid, bool create)
{
    bool found = false;
    HASHACTION action = create ? HASH_ENTER : HASH_FIND;
    PgStat_StatDBEntry* entry = (PgStat_StatDBEntry*)hash_search(dbhash, &dbid, action, &found);
    if (entry == NULL)
        return NULL;

    if (!found && create) {
        errno_t rc = memset_s(entry, sizeof(PgStat_StatDBEntry), 0, sizeof(PgStat_StatDBEntry));
        securec_check(rc, "\0", "\0");
        entry->databaseid = dbid;

        HASHCTL hash_ctl;
        rc = memset_s(&hash_ctl, sizeof(hash_ctl), 0, sizeof(hash_ctl));
        securec_check(rc, "\0", "\0");
        hash_ctl.keysize = sizeof(PgStat_StatTabKey);
        hash_ctl.entrysize = sizeof(PgStat_StatTabEntry);
        hash_ctl.hash = tag_hash;
        hash_ctl.hcxt = mcxt;
        entry->tables =
            hash_create("Per-database table", PGSTAT_SNAPSHOT_TAB_HASH_SIZE, &hash_ctl,
                HASH_ELEM | HASH_FUNCTION | HASH_CONTEXT);

        hash_ctl.keysize = sizeof(Oid);
        hash_ctl.entrysize = sizeof(PgStat_StatFuncEntry);
        hash_ctl.hash = oid_hash;
        entry->functions =
            hash_create("Per-database function", PGSTAT_SNAPSHOT_FUNC_HASH_SIZE, &hash_ctl,
                HASH_ELEM | HASH_FUNCTION | HASH_CONTEXT);
    }

    return entry;
}

void pgstat_shared_copy_snapshot(Oid onlydb, MemoryContext mcxt, HTAB** out_dbhash, PgStat_GlobalStats* out_global)
{
    if (out_dbhash != NULL)
        *out_dbhash = NULL;
    if (out_global != NULL)
        (void)memset_s(out_global, sizeof(PgStat_GlobalStats), 0, sizeof(PgStat_GlobalStats));

    if (g_pgstat_shared == NULL || mcxt == NULL)
        return;

    MemoryContext old = MemoryContextSwitchTo(mcxt);

    HASHCTL hash_ctl;
    errno_t rc = memset_s(&hash_ctl, sizeof(hash_ctl), 0, sizeof(hash_ctl));
    securec_check(rc, "\0", "\0");
    hash_ctl.keysize = sizeof(Oid);
    hash_ctl.entrysize = sizeof(PgStat_StatDBEntry);
    hash_ctl.hash = oid_hash;
    hash_ctl.hcxt = mcxt;

    HTAB* dbhash =
        hash_create("Databases hash", PGSTAT_SNAPSHOT_DB_HASH_SIZE, &hash_ctl, HASH_ELEM | HASH_FUNCTION | HASH_CONTEXT);

    if (out_dbhash != NULL)
        *out_dbhash = dbhash;

    LWLock* glock = pgstat_shared_global_lock();
    if (glock != NULL && out_global != NULL) {
        LWLockAcquire(glock, LW_SHARED);
        *out_global = g_pgstat_shared->global_stats;
        LWLockRelease(glock);
    }

    pgstat_lock_all(g_pgstat_shared->db_locks, PGSTAT_DB_NPARTITIONS, LW_SHARED);

    HASH_SEQ_STATUS hstat;
    hash_seq_init(&hstat, g_pgstat_shared->db_hash);
    for (;;) {
        PgStatSharedDBEntry* sdb = (PgStatSharedDBEntry*)hash_seq_search(&hstat);
        if (sdb == NULL)
            break;
        if (!pgstat_dbid_visible(sdb->databaseid, onlydb))
            continue;
        PgStat_StatDBEntry* dbentry = snapshot_get_db_entry(dbhash, mcxt, sdb->databaseid, true);
        if (dbentry == NULL)
            continue;
        dbentry->n_xact_commit = sdb->n_xact_commit;
        dbentry->n_xact_rollback = sdb->n_xact_rollback;
        dbentry->n_blocks_fetched = sdb->n_blocks_fetched;
        dbentry->n_blocks_hit = sdb->n_blocks_hit;
        dbentry->n_cu_mem_hit = sdb->n_cu_mem_hit;
        dbentry->n_cu_hdd_sync = sdb->n_cu_hdd_sync;
        dbentry->n_cu_hdd_asyn = sdb->n_cu_hdd_asyn;
        dbentry->n_tuples_returned = sdb->n_tuples_returned;
        dbentry->n_tuples_fetched = sdb->n_tuples_fetched;
        dbentry->n_tuples_inserted = sdb->n_tuples_inserted;
        dbentry->n_tuples_updated = sdb->n_tuples_updated;
        dbentry->n_tuples_deleted = sdb->n_tuples_deleted;
        dbentry->last_autovac_time = sdb->last_autovac_time;
        dbentry->n_conflict_tablespace = sdb->n_conflict_tablespace;
        dbentry->n_conflict_lock = sdb->n_conflict_lock;
        dbentry->n_conflict_snapshot = sdb->n_conflict_snapshot;
        dbentry->n_conflict_bufferpin = sdb->n_conflict_bufferpin;
        dbentry->n_conflict_startup_deadlock = sdb->n_conflict_startup_deadlock;
        dbentry->n_temp_files = sdb->n_temp_files;
        dbentry->n_temp_bytes = sdb->n_temp_bytes;
        dbentry->n_deadlocks = sdb->n_deadlocks;
        dbentry->n_block_read_time = sdb->n_block_read_time;
        dbentry->n_block_write_time = sdb->n_block_write_time;
        dbentry->n_mem_mbytes_reserved = sdb->n_mem_mbytes_reserved;
        dbentry->stat_reset_timestamp = sdb->stat_reset_timestamp;
    }

    pgstat_unlock_all(g_pgstat_shared->db_locks, PGSTAT_DB_NPARTITIONS);

    pgstat_lock_all(g_pgstat_shared->tab_locks, PGSTAT_TAB_NPARTITIONS, LW_SHARED);

    HASH_SEQ_STATUS tstat;
    hash_seq_init(&tstat, g_pgstat_shared->tab_hash);
    for (;;) {
        PgStatSharedTabEntry* stab = (PgStatSharedTabEntry*)hash_seq_search(&tstat);
        if (stab == NULL)
            break;
        if (!pgstat_dbid_visible(stab->key.databaseid, onlydb))
            continue;

        PgStat_StatDBEntry* dbentry = snapshot_get_db_entry(dbhash, mcxt, stab->key.databaseid, true);
        if (dbentry == NULL || dbentry->tables == NULL)
            continue;

        PgStat_StatTabKey tabkey;
        tabkey.tableid = stab->key.tableid;
        tabkey.statFlag = stab->key.statFlag;

        bool found = false;
        PgStat_StatTabEntry* tabentry =
            (PgStat_StatTabEntry*)hash_search(dbentry->tables, &tabkey, HASH_ENTER, &found);
        if (tabentry == NULL)
            continue;

        tabentry->tablekey = tabkey;
        tabentry->numscans = stab->numscans;
        tabentry->lastscan = stab->lastscan;
        tabentry->tuples_returned = stab->tuples_returned;
        tabentry->tuples_fetched = stab->tuples_fetched;
        tabentry->tuples_inserted = stab->tuples_inserted;
        tabentry->tuples_updated = stab->tuples_updated;
        tabentry->tuples_deleted = stab->tuples_deleted;
        tabentry->tuples_inplace_updated = stab->tuples_inplace_updated;
        tabentry->tuples_hot_updated = stab->tuples_hot_updated;
        tabentry->n_live_tuples = stab->n_live_tuples;
        tabentry->n_dead_tuples = stab->n_dead_tuples;
        tabentry->changes_since_analyze = stab->changes_since_analyze;
        tabentry->blocks_fetched = stab->blocks_fetched;
        tabentry->blocks_hit = stab->blocks_hit;
        tabentry->cu_mem_hit = stab->cu_mem_hit;
        tabentry->cu_hdd_sync = stab->cu_hdd_sync;
        tabentry->cu_hdd_asyn = stab->cu_hdd_asyn;
        tabentry->success_prune_cnt = stab->success_prune_cnt;
        tabentry->total_prune_cnt = stab->total_prune_cnt;
        tabentry->vacuum_timestamp = stab->vacuum_timestamp;
        tabentry->vacuum_count = stab->vacuum_count;
        tabentry->autovac_vacuum_timestamp = stab->autovac_vacuum_timestamp;
        tabentry->autovac_vacuum_count = stab->autovac_vacuum_count;
        tabentry->analyze_timestamp = stab->analyze_timestamp;
        tabentry->analyze_count = stab->analyze_count;
        tabentry->autovac_analyze_timestamp = stab->autovac_analyze_timestamp;
        tabentry->autovac_analyze_count = stab->autovac_analyze_count;
        tabentry->data_changed_timestamp = stab->data_changed_timestamp;
        tabentry->autovac_status = stab->autovac_status;
    }

    pgstat_unlock_all(g_pgstat_shared->tab_locks, PGSTAT_TAB_NPARTITIONS);

    pgstat_lock_all(g_pgstat_shared->func_locks, PGSTAT_FUNC_NPARTITIONS, LW_SHARED);

    HASH_SEQ_STATUS fstat;
    hash_seq_init(&fstat, g_pgstat_shared->func_hash);
    for (;;) {
        PgStatSharedFuncEntry* sfunc = (PgStatSharedFuncEntry*)hash_seq_search(&fstat);
        if (sfunc == NULL)
            break;
        if (!pgstat_dbid_visible(sfunc->key.databaseid, onlydb))
            continue;

        PgStat_StatDBEntry* dbentry = snapshot_get_db_entry(dbhash, mcxt, sfunc->key.databaseid, true);
        if (dbentry == NULL || dbentry->functions == NULL)
            continue;

        bool found = false;
        PgStat_StatFuncEntry* funcentry =
            (PgStat_StatFuncEntry*)hash_search(dbentry->functions, &sfunc->key.functionid, HASH_ENTER, &found);
        if (funcentry == NULL)
            continue;

        funcentry->functionid = sfunc->key.functionid;
        funcentry->f_numcalls = sfunc->f_numcalls;
        funcentry->f_total_time = sfunc->f_total_time;
        funcentry->f_self_time = sfunc->f_self_time;
    }

    pgstat_unlock_all(g_pgstat_shared->func_locks, PGSTAT_FUNC_NPARTITIONS);

    MemoryContextSwitchTo(old);
}

static void pgstat_shared_clear_all_hashes(void)
{
    if (g_pgstat_shared == NULL)
        return;

    pgstat_lock_all(g_pgstat_shared->db_locks, PGSTAT_DB_NPARTITIONS, LW_EXCLUSIVE);
    HASH_SEQ_STATUS dbseq;
    hash_seq_init(&dbseq, g_pgstat_shared->db_hash);
    for (;;) {
        PgStatSharedDBEntry* entry = (PgStatSharedDBEntry*)hash_seq_search(&dbseq);
        if (entry == NULL)
            break;
        Oid dbid = entry->databaseid;
        (void)hash_search(g_pgstat_shared->db_hash, &dbid, HASH_REMOVE, NULL);
    }
    pgstat_unlock_all(g_pgstat_shared->db_locks, PGSTAT_DB_NPARTITIONS);

    pgstat_lock_all(g_pgstat_shared->tab_locks, PGSTAT_TAB_NPARTITIONS, LW_EXCLUSIVE);
    HASH_SEQ_STATUS tabseq;
    hash_seq_init(&tabseq, g_pgstat_shared->tab_hash);
    for (;;) {
        PgStatSharedTabEntry* entry = (PgStatSharedTabEntry*)hash_seq_search(&tabseq);
        if (entry == NULL)
            break;
        PgStatSharedTabKey key = entry->key;
        (void)hash_search(g_pgstat_shared->tab_hash, &key, HASH_REMOVE, NULL);
    }
    pgstat_unlock_all(g_pgstat_shared->tab_locks, PGSTAT_TAB_NPARTITIONS);

    pgstat_lock_all(g_pgstat_shared->func_locks, PGSTAT_FUNC_NPARTITIONS, LW_EXCLUSIVE);
    HASH_SEQ_STATUS funcseq;
    hash_seq_init(&funcseq, g_pgstat_shared->func_hash);
    for (;;) {
        PgStatSharedFuncEntry* entry = (PgStatSharedFuncEntry*)hash_seq_search(&funcseq);
        if (entry == NULL)
            break;
        PgStatSharedFuncKey key = entry->key;
        (void)hash_search(g_pgstat_shared->func_hash, &key, HASH_REMOVE, NULL);
    }
    pgstat_unlock_all(g_pgstat_shared->func_locks, PGSTAT_FUNC_NPARTITIONS);
}

void pgstat_shared_import_snapshot(HTAB* dbhash, const PgStat_GlobalStats* global)
{
    if (g_pgstat_shared == NULL || dbhash == NULL)
        return;

    pgstat_shared_clear_all_hashes();

    if (global != NULL) {
        LWLock* glock = pgstat_shared_global_lock();
        if (glock != NULL) {
            LWLockAcquire(glock, LW_EXCLUSIVE);
            g_pgstat_shared->global_stats = *global;
            LWLockRelease(glock);
        }
    }

    HASH_SEQ_STATUS hstat;
    hash_seq_init(&hstat, dbhash);
    for (;;) {
        PgStat_StatDBEntry* dbentry = (PgStat_StatDBEntry*)hash_seq_search(&hstat);
        if (dbentry == NULL)
            break;

        LWLock* dblock = NULL;
        PgStatSharedDBEntry* sdb =
            pgstat_shared_get_db_entry(dbentry->databaseid, true, LW_EXCLUSIVE, &dblock, NULL);
        if (sdb != NULL) {
            sdb->n_xact_commit = dbentry->n_xact_commit;
            sdb->n_xact_rollback = dbentry->n_xact_rollback;
            sdb->n_blocks_fetched = dbentry->n_blocks_fetched;
            sdb->n_blocks_hit = dbentry->n_blocks_hit;
            sdb->n_cu_mem_hit = dbentry->n_cu_mem_hit;
            sdb->n_cu_hdd_sync = dbentry->n_cu_hdd_sync;
            sdb->n_cu_hdd_asyn = dbentry->n_cu_hdd_asyn;
            sdb->n_tuples_returned = dbentry->n_tuples_returned;
            sdb->n_tuples_fetched = dbentry->n_tuples_fetched;
            sdb->n_tuples_inserted = dbentry->n_tuples_inserted;
            sdb->n_tuples_updated = dbentry->n_tuples_updated;
            sdb->n_tuples_deleted = dbentry->n_tuples_deleted;
            sdb->last_autovac_time = dbentry->last_autovac_time;
            sdb->n_conflict_tablespace = dbentry->n_conflict_tablespace;
            sdb->n_conflict_lock = dbentry->n_conflict_lock;
            sdb->n_conflict_snapshot = dbentry->n_conflict_snapshot;
            sdb->n_conflict_bufferpin = dbentry->n_conflict_bufferpin;
            sdb->n_conflict_startup_deadlock = dbentry->n_conflict_startup_deadlock;
            sdb->n_temp_files = dbentry->n_temp_files;
            sdb->n_temp_bytes = dbentry->n_temp_bytes;
            sdb->n_deadlocks = dbentry->n_deadlocks;
            sdb->n_block_read_time = dbentry->n_block_read_time;
            sdb->n_block_write_time = dbentry->n_block_write_time;
            sdb->n_mem_mbytes_reserved = dbentry->n_mem_mbytes_reserved;
            sdb->stat_reset_timestamp = dbentry->stat_reset_timestamp;
            pgstat_shared_release_lock(dblock);
        }

        if (dbentry->tables != NULL) {
            HASH_SEQ_STATUS tstat;
            hash_seq_init(&tstat, dbentry->tables);
            for (;;) {
                PgStat_StatTabEntry* tabentry = (PgStat_StatTabEntry*)hash_seq_search(&tstat);
                if (tabentry == NULL)
                    break;
                LWLock* tlock = NULL;
                PgStatSharedTabEntry* stab = pgstat_shared_get_tab_entry(dbentry->databaseid,
                    tabentry->tablekey.tableid, tabentry->tablekey.statFlag, true, LW_EXCLUSIVE, &tlock, NULL);
                if (stab != NULL) {
                    stab->numscans = tabentry->numscans;
                    stab->lastscan = tabentry->lastscan;
                    stab->tuples_returned = tabentry->tuples_returned;
                    stab->tuples_fetched = tabentry->tuples_fetched;
                    stab->tuples_inserted = tabentry->tuples_inserted;
                    stab->tuples_updated = tabentry->tuples_updated;
                    stab->tuples_deleted = tabentry->tuples_deleted;
                    stab->tuples_inplace_updated = tabentry->tuples_inplace_updated;
                    stab->tuples_hot_updated = tabentry->tuples_hot_updated;
                    stab->n_live_tuples = tabentry->n_live_tuples;
                    stab->n_dead_tuples = tabentry->n_dead_tuples;
                    stab->changes_since_analyze = tabentry->changes_since_analyze;
                    stab->blocks_fetched = tabentry->blocks_fetched;
                    stab->blocks_hit = tabentry->blocks_hit;
                    stab->cu_mem_hit = tabentry->cu_mem_hit;
                    stab->cu_hdd_sync = tabentry->cu_hdd_sync;
                    stab->cu_hdd_asyn = tabentry->cu_hdd_asyn;
                    stab->success_prune_cnt = tabentry->success_prune_cnt;
                    stab->total_prune_cnt = tabentry->total_prune_cnt;
                    stab->vacuum_timestamp = tabentry->vacuum_timestamp;
                    stab->vacuum_count = tabentry->vacuum_count;
                    stab->autovac_vacuum_timestamp = tabentry->autovac_vacuum_timestamp;
                    stab->autovac_vacuum_count = tabentry->autovac_vacuum_count;
                    stab->analyze_timestamp = tabentry->analyze_timestamp;
                    stab->analyze_count = tabentry->analyze_count;
                    stab->autovac_analyze_timestamp = tabentry->autovac_analyze_timestamp;
                    stab->autovac_analyze_count = tabentry->autovac_analyze_count;
                    stab->data_changed_timestamp = tabentry->data_changed_timestamp;
                    stab->autovac_status = tabentry->autovac_status;
                    pgstat_shared_release_lock(tlock);
                }
            }
        }

        if (dbentry->functions != NULL) {
            HASH_SEQ_STATUS fstat;
            hash_seq_init(&fstat, dbentry->functions);
            for (;;) {
                PgStat_StatFuncEntry* funcentry = (PgStat_StatFuncEntry*)hash_seq_search(&fstat);
                if (funcentry == NULL)
                    break;
                LWLock* flock = NULL;
                PgStatSharedFuncEntry* sfunc =
                    pgstat_shared_get_func_entry(dbentry->databaseid, funcentry->functionid, true, LW_EXCLUSIVE,
                        &flock, NULL);
                if (sfunc != NULL) {
                    sfunc->f_numcalls = funcentry->f_numcalls;
                    sfunc->f_total_time = funcentry->f_total_time;
                    sfunc->f_self_time = funcentry->f_self_time;
                    pgstat_shared_release_lock(flock);
                }
            }
        }
    }
}
