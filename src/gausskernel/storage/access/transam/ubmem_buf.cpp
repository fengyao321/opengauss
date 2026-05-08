/* USE_UB_TXN_CACHE - BEGIN */
#include "access/ubmem_buf.h"
#include "knl/knl_thread.h"
#include "access/clog.h"
#include "access/csnlog.h"
#include "ddes/dms/ss_init.h"
#include "ddes/dms/ss_transaction.h"
#include "ddes/dms/ss_xmin.h"
#include "storage/ubs_mem.h"
#include "utils/elog.h"
#include <string.h>
#include <pwd.h>
#include <unistd.h>

static const char* GetOSUserName(char *buf, size_t len)
{
    struct passwd *pw = getpwuid(getuid());
    if (pw == nullptr || pw->pw_name == nullptr) {
        ereport(ERROR, (errmsg("Failed to get OS user name")));
        return nullptr;
    }
    int ret = snprintf(buf, len, "%s", pw->pw_name);
    if (ret < 0 || (size_t)ret >= len) {
        ereport(ERROR, (errmsg("OS user name too long")));
        return nullptr;
    }
    return buf;
}

void UBMemRegionName(const char *host_name, char *region_name, size_t len)
{
    if (host_name == nullptr || region_name == nullptr) {
        ereport(ERROR, (errmsg("Invalid arguments")));
        return;
    }
    int ret = snprintf(region_name, len, "mem_pool_%s", host_name);
    if (ret < 0 || (size_t)ret >= len) {
        ereport(ERROR, (errmsg("Failed to format region name")));
    }
}

bool UBMemRegionInit()
{
    char host_name[UB_MAX_HOST_NAME_LENGTH + 1];
    if (gethostname(host_name, sizeof(host_name)) != 0) {
        ereport(ERROR, (errmsg("Failed to get host name")));
        return false;
    }
    host_name[sizeof(host_name) - 1] = '\0';

    ubsmem_regions_t regions;
    ubsmem_region_attributes_t region;
    int ret = ubsmem_lookup_regions(&regions);
    if (ret != UBSM_OK) {
        ereport(ERROR, (errmsg("Failed to lookup shm regions, error: %d", ret)));
        return false;
    }

    region = regions.region[0];
    for (int i = 0; i < region.host_num; i++) {
        region.hosts[i].affinity = false;
        if (strcmp(region.hosts[i].host_name, host_name) == 0) {
            region.hosts[i].affinity = true;
        }
    }

    char region_name[UB_MAX_REGION_NAME_DESC_LENGTH];
    UBMemRegionName(host_name, region_name, sizeof(region_name));

    ret = ubsmem_create_region(region_name, 0, &region);
    if (ret != UBSM_OK && ret != UBSM_ERR_ALREADY_EXIST) {
        ereport(ERROR, (errmsg("Failed to create region. ret: %d", ret)));
        return false;
    }
    return true;
}

bool UBSMemAllocate(const char *buffer_name, size_t buffer_size)
{
    char host_name[UB_MAX_HOST_NAME_LENGTH + 1];
    if (gethostname(host_name, sizeof(host_name)) != 0) {
        ereport(ERROR, (errmsg("Failed to get host name")));
        return false;
    }
    host_name[sizeof(host_name) - 1] = '\0';

    char region_name[UB_MAX_REGION_NAME_DESC_LENGTH];
    UBMemRegionName(host_name, region_name, sizeof(region_name));

    ereport(LOG, (errmsg("[UB DEBUG] UBSMemAllocate: region_name=%s, buffer_name=%s, size=%lu",
                         region_name, buffer_name, buffer_size)));

    int ret = ubsmem_shmem_allocate(region_name, buffer_name, buffer_size, 0600,
                                    UBSM_FLAG_ONLY_IMPORT_NONCACHE | UBSM_FLAG_WR_DELAY_COMP);
    if (ret != UBSM_OK && ret != UBSM_ERR_ALREADY_EXIST) {
        ereport(ERROR, (errmsg("Failed to allocate UB shared memory for %s: %d", buffer_name, ret)));
        return false;
    }

    ret = ubsmem_destroy_region(region_name);
    if (ret != UBSM_OK) {
        ereport(ERROR, (errmsg("Failed to destroy region. ret: %d", ret)));
        return false;
    }
    
    return true;
}

bool UBSMemLogBufferCreate()
{
    const size_t MIN_SIZE = 128 << 20;
    const size_t ALIGN_SIZE = 4 << 20;
    const size_t GB_ALIGN = 1ULL << 30;

    size_t clog_buf_size = UBCLogBufferSize();
    size_t csnlog_buf_size = UBCSNLogBufferSize();
    size_t xmin_buf_size = UBOldestXminBufferSize();
    size_t snapshot_buf_size = UBSnapshotBufferSize();

    size_t clog_size = (clog_buf_size < MIN_SIZE) ? MIN_SIZE :
                       ((clog_buf_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE);
    size_t csnlog_size = (csnlog_buf_size < MIN_SIZE) ? MIN_SIZE :
                         ((csnlog_buf_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE);
    size_t xmin_size = (xmin_buf_size < MIN_SIZE) ? MIN_SIZE :
                       ((xmin_buf_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE);
    size_t snapshot_size = (snapshot_buf_size < MIN_SIZE) ? MIN_SIZE :
                           ((snapshot_buf_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE);

    size_t total_size = sizeof(UBShmControlBlock) + clog_size + csnlog_size + xmin_size + snapshot_size;
    total_size = (total_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE;
    total_size = (total_size + GB_ALIGN - 1) / GB_ALIGN * GB_ALIGN;

    char user_name[128];
    if (GetOSUserName(user_name, sizeof(user_name)) == nullptr) {
        return false;
    }

    char local_shm_name[UB_MAX_SHM_NAME_LENGTH];
    char primary_shm_name[UB_MAX_SHM_NAME_LENGTH];
    snprintf(local_shm_name, sizeof(local_shm_name), "ub_node%02d_%s_txn_cache", 
             SS_MY_INST_ID, user_name);
    snprintf(primary_shm_name, sizeof(primary_shm_name), "ub_node%02d_%s_txn_cache", 
             SS_PRIMARY_ID, user_name);
    // snprintf(primary_shm_name, sizeof(primary_shm_name), "ub_node00_%s_txn_cache", 
    //          user_name);

    ereport(LOG, (errmsg("[UB DEBUG] Local node=%d, Primary node=%d", SS_MY_INST_ID, SS_PRIMARY_ID)));
    ereport(LOG, (errmsg("[UB DEBUG] Local shm_name=%s, Primary shm_name=%s", local_shm_name, primary_shm_name)));

    if (!UBSMemAllocate(local_shm_name, total_size))
        return false;

    ereport(LOG, (errmsg("[UB DEBUG] ubsmem_shmem_map: name=%s, size=%lu", primary_shm_name, total_size)));

    void *addr = nullptr;
    int ret = ubsmem_shmem_map(nullptr, total_size, PROT_READ | PROT_WRITE,
                               MAP_SHARED, primary_shm_name, 0, &addr);
    if (ret != UBSM_OK || addr == nullptr) {
        ereport(ERROR, (errmsg("Failed to map UB shared memory: %d, primary_shm_name=%s", ret, primary_shm_name)));
        return false;
    }

    ereport(LOG, (errmsg("[UB DEBUG] ubsmem_shmem_map success: addr=%p", addr)));

    UBShmControlBlock *ctrl = (UBShmControlBlock *)addr;
    bool new_created = (ctrl->total_size.load(std::memory_order_relaxed) == 0);

    if (new_created) {
        ctrl->total_size.store(total_size, std::memory_order_release);
        ctrl->clog_offset.store(sizeof(UBShmControlBlock), std::memory_order_release);
        ctrl->clog_size.store(clog_size, std::memory_order_release);
        ctrl->clog_inited.store(false, std::memory_order_release);

        uint64 csnlog_off = sizeof(UBShmControlBlock) + clog_size;
        ctrl->csnlog_offset.store(csnlog_off, std::memory_order_release);
        ctrl->csnlog_size.store(csnlog_size, std::memory_order_release);
        ctrl->csnlog_inited.store(false, std::memory_order_release);

        uint64 oldest_xmin_off = csnlog_off + csnlog_size;
        ctrl->oldest_xmin_offset.store(oldest_xmin_off, std::memory_order_release);
        ctrl->oldest_xmin_size.store(xmin_size, std::memory_order_release);
        ctrl->oldest_xmin_inited.store(false, std::memory_order_release);

        uint64 snapshot_off = oldest_xmin_off + xmin_size;
        ctrl->snapshot_offset.store(snapshot_off, std::memory_order_release);
        ctrl->snapshot_size.store(snapshot_size, std::memory_order_release);
        ctrl->snapshot_inited.store(false, std::memory_order_release);
    } else {
        if (!UBSMemVerification((char *)addr)) {
            ereport(ERROR, (errmsg("UB shared memory verification failed for reused memory")));
            return false;
        }
    }

    if (!ctrl->clog_inited.load(std::memory_order_acquire)) {
        UBCLogBuffer *clog_buf = (UBCLogBuffer *)((char *)addr + ctrl->clog_offset.load());
        UBCLogBufferInit(clog_buf);
        ctrl->clog_inited.store(true, std::memory_order_release);
    }
    if (!ctrl->csnlog_inited.load(std::memory_order_acquire)) {
        UBCSNLogBuffer *csnlog_buf = (UBCSNLogBuffer *)((char *)addr + ctrl->csnlog_offset.load());
        UBCSNLogBufferInit(csnlog_buf);
        ctrl->csnlog_inited.store(true, std::memory_order_release);
    }
    if (!ctrl->oldest_xmin_inited.load(std::memory_order_acquire)) {
        UBOldestXminBuffer *xmin_buf = (UBOldestXminBuffer *)((char *)addr + ctrl->oldest_xmin_offset.load());
        UBOldestXminBufferInit(xmin_buf);
        ctrl->oldest_xmin_inited.store(true, std::memory_order_release);
    }
    if (!ctrl->snapshot_inited.load(std::memory_order_acquire)) {
        UBSnapshotBuffer *snapshot_buf = (UBSnapshotBuffer *)((char *)addr + ctrl->snapshot_offset.load());
        UBSnapshotBufferInit(snapshot_buf);
        ctrl->snapshot_inited.store(true, std::memory_order_release);
    }

    g_instance.shmem_cxt.UBTxnCachePtr = (char *)addr;

    ereport(LOG, (errmsg("UB shared memory initialized (size: %lu, %s)",
                         total_size, new_created ? "new create" : "reused")));
    ereport(LOG, (errmsg("[UB DEBUG] UBTxnCachePtr=%p, clog_offset=%lu, csnlog_offset=%lu, oldest_xmin_offset=%lu, snapshot_offset=%lu",
                         addr, ctrl->clog_offset.load(), ctrl->csnlog_offset.load(), 
                         ctrl->oldest_xmin_offset.load(), ctrl->snapshot_offset.load())));
    return true;
}

bool UBSMemFinalize()
{
    char *addr = g_instance.shmem_cxt.UBTxnCachePtr;
    if (addr != nullptr) {
        UBShmControlBlock *ctrl = (UBShmControlBlock *)addr;
        size_t length = (size_t)ctrl->total_size.load(std::memory_order_acquire);
        int ret = ubsmem_shmem_unmap(addr, length);
        if (ret != UBSM_OK) {
            ereport(WARNING, (errmsg("Failed to unmap UB shared memory: %d", ret)));
        }
        g_instance.shmem_cxt.UBTxnCachePtr = nullptr;
    }

    int ret = ubsmem_finalize();
    if (ret != UBSM_OK) {
        ereport(ERROR, (errmsg("Failed to finalize ubs-mem. ret: %d", ret)));
        return false;
    }
    return true;
}

bool UBSMemVerification(char *ub_txn_cache_ptr)
{
    if (ub_txn_cache_ptr == nullptr) {
        ereport(WARNING, (errmsg("UB shared memory pointer is null")));
        return false;
    }

    UBShmControlBlock *ctrl = (UBShmControlBlock *)ub_txn_cache_ptr;

    uint64 total_size = ctrl->total_size.load(std::memory_order_acquire);
    uint64 clog_offset = ctrl->clog_offset.load(std::memory_order_acquire);
    uint64 clog_size = ctrl->clog_size.load(std::memory_order_acquire);
    uint64 csnlog_offset = ctrl->csnlog_offset.load(std::memory_order_acquire);
    uint64 csnlog_size = ctrl->csnlog_size.load(std::memory_order_acquire);
    uint64 oldest_xmin_offset = ctrl->oldest_xmin_offset.load(std::memory_order_acquire);
    uint64 oldest_xmin_size = ctrl->oldest_xmin_size.load(std::memory_order_acquire);
    uint64 snapshot_offset = ctrl->snapshot_offset.load(std::memory_order_acquire);
    uint64 snapshot_size = ctrl->snapshot_size.load(std::memory_order_acquire);

    bool valid = true;

    uint64 expected_clog_offset = sizeof(UBShmControlBlock);
    if (clog_offset != expected_clog_offset) {
        ereport(WARNING, (errmsg("UB memory verification failed: clog_offset mismatch. "
                                 "expected: %lu, actual: %lu", expected_clog_offset, clog_offset)));
        valid = false;
    }

    uint64 expected_csnlog_offset = clog_offset + clog_size;
    if (csnlog_offset != expected_csnlog_offset) {
        ereport(WARNING, (errmsg("UB memory verification failed: csnlog_offset mismatch. "
                                 "expected: %lu (clog_offset %lu + clog_size %lu), actual: %lu",
                                 expected_csnlog_offset, clog_offset, clog_size, csnlog_offset)));
        valid = false;
    }

    uint64 expected_oldest_xmin_offset = csnlog_offset + csnlog_size;
    if (oldest_xmin_offset != expected_oldest_xmin_offset) {
        ereport(WARNING, (errmsg("UB memory verification failed: oldest_xmin_offset mismatch. "
                                 "expected: %lu (csnlog_offset %lu + csnlog_size %lu), actual: %lu",
                                 expected_oldest_xmin_offset, csnlog_offset, csnlog_size, oldest_xmin_offset)));
        valid = false;
    }

    uint64 expected_snapshot_offset = oldest_xmin_offset + oldest_xmin_size;
    if (snapshot_offset != expected_snapshot_offset) {
        ereport(WARNING, (errmsg("UB memory verification failed: snapshot_offset mismatch. "
                                 "expected: %lu (oldest_xmin_offset %lu + oldest_xmin_size %lu), actual: %lu",
                                 expected_snapshot_offset, oldest_xmin_offset, oldest_xmin_size, snapshot_offset)));
        valid = false;
    }

    if (valid) {
        ereport(LOG, (errmsg("UB memory verification passed. "
                             "total_size: %lu, clog: [%lu, %lu], csnlog: [%lu, %lu], oldest_xmin: [%lu, %lu], snapshot: [%lu, %lu]",
                             total_size, clog_offset, clog_size, csnlog_offset, csnlog_size,
                             oldest_xmin_offset, oldest_xmin_size, snapshot_offset, snapshot_size)));
    }

    return valid;
}

/* USE_UB_TXN_CACHE - END */