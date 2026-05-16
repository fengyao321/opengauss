/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 *
 * openGauss is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 * EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 * MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 * See the Mulan PSL v2 for more details.
 * ---------------------------------------------------------------------------------------
 * ubmem_buf.cpp
 * UB transaction cache buffer manager
 *
 * src/gausskernel/storage/access/transam/ubmem_buf.cpp
 * ---------------------------------------------------------------------------------------
 */

/* USE_UB_TXN_CACHE - BEGIN */
#include <string.h>
#include <pwd.h>
#include <unistd.h>
#include <sys/time.h>
#include "knl/knl_thread.h"
#include "access/clog.h"
#include "access/csnlog.h"
#include "ddes/dms/ss_init.h"
#include "ddes/dms/ss_transaction.h"
#include "ddes/dms/ss_xmin.h"
#include "storage/ubs_mem.h"
#include "utils/elog.h"
#include "access/ub_sigbus_handler.h"
#include "securec_check.h"
#include "access/ubmem_buf.h"

static const char* GetOSUserName(char *buf, size_t len)
{
    struct passwd *pw = getpwuid(getuid());
    if (pw == nullptr || pw->pw_name == nullptr) {
        ereport(ERROR, (errmsg("Failed to get OS user name")));
        return nullptr;
    }
    errno_t rc = snprintf_s(buf, len, len - 1, "%s", pw->pw_name);
    securec_check_ss_c(rc, "\0", "\0");
    return buf;
}

static bool GetUBSMemName(int32 instance_id, char *shm_name, size_t shm_name_size)
{
    char user_name[128];
    if (GetOSUserName(user_name, sizeof(user_name)) == nullptr) {
        ereport(ERROR, (errmsg("Failed to get OS user name for instance %d", instance_id)));
        return false;
    }
    
    errno_t rc = snprintf_s(shm_name, shm_name_size, shm_name_size - 1,
                         "ub_node%02d_%s_txn_cache", instance_id, user_name);
    securec_check_ss_c(rc, "\0", "\0");
    return true;
}

void UBMemRegionName(const char *host_name, char *region_name, size_t len)
{
    if (host_name == nullptr || region_name == nullptr) {
        ereport(ERROR, (errmsg("Invalid arguments")));
        return;
    }
    errno_t rc = snprintf_s(region_name, len, len - 1, "mem_pool_%s", host_name);
    securec_check_ss_c(rc, "\0", "\0");
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

static void InitUBSMemControlBlock(UBShmControlBlock *ctrl, size_t total_size, size_t clog_size,
                                   size_t csnlog_size, size_t xmin_size, size_t snapshot_size)
{
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
}

static void InitUBSMemBuffer(UBShmControlBlock *ctrl, char *base_addr)
{
    if (!ctrl->clog_inited.load(std::memory_order_acquire)) {
        UBCLogBuffer *clog_buf = (UBCLogBuffer *)(base_addr + ctrl->clog_offset.load());
        UBCLogBufferInit(clog_buf);
        ctrl->clog_inited.store(true, std::memory_order_release);
    }
    if (!ctrl->csnlog_inited.load(std::memory_order_acquire)) {
        UBCSNLogBuffer *csnlog_buf = (UBCSNLogBuffer *)(base_addr + ctrl->csnlog_offset.load());
        UBCSNLogBufferInit(csnlog_buf);
        ctrl->csnlog_inited.store(true, std::memory_order_release);
    }
    if (!ctrl->oldest_xmin_inited.load(std::memory_order_acquire)) {
        UBOldestXminBuffer *xmin_buf = (UBOldestXminBuffer *)(base_addr + ctrl->oldest_xmin_offset.load());
        UBOldestXminBufferInit(xmin_buf);
        ctrl->oldest_xmin_inited.store(true, std::memory_order_release);
    }
    if (!ctrl->snapshot_inited.load(std::memory_order_acquire)) {
        UBSnapshotBuffer *snapshot_buf = (UBSnapshotBuffer *)(base_addr + ctrl->snapshot_offset.load());
        UBSnapshotBufferInit(snapshot_buf);
        ctrl->snapshot_inited.store(true, std::memory_order_release);
    }
}

static UBShmStdSize CalUBSMemSize(void)
{
    const size_t MIN_SIZE = 128 << 20;
    const size_t ALIGN_SIZE = 4 << 20;
    const size_t GB_ALIGN = 1ULL << 30;

    size_t clog_buf_size = UBCLogBufferSize();
    size_t csnlog_buf_size = UBCSNLogBufferSize();
    size_t xmin_buf_size = UBOldestXminBufferSize();
    size_t snapshot_buf_size = UBSnapshotBufferSize();

    UBShmStdSize sz;
    sz.clog_size = (clog_buf_size < MIN_SIZE) ? MIN_SIZE :
                   ((clog_buf_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE);
    sz.csnlog_size = (csnlog_buf_size < MIN_SIZE) ? MIN_SIZE :
                     ((csnlog_buf_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE);
    sz.xmin_size = (xmin_buf_size < MIN_SIZE) ? MIN_SIZE :
                   ((xmin_buf_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE);
    sz.snapshot_size = (snapshot_buf_size < MIN_SIZE) ? MIN_SIZE :
                       ((snapshot_buf_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE);

    sz.total_size = sizeof(UBShmControlBlock) + sz.clog_size + sz.csnlog_size + sz.xmin_size + sz.snapshot_size;
    sz.total_size = (sz.total_size + ALIGN_SIZE - 1) / ALIGN_SIZE * ALIGN_SIZE;
    sz.total_size = (sz.total_size + GB_ALIGN - 1) / GB_ALIGN * GB_ALIGN;

    return sz;
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
    UBShmStdSize sz = CalUBSMemSize();

    char user_name[128];
    if (GetOSUserName(user_name, sizeof(user_name)) == nullptr) {
        return false;
    }

    char local_shm_name[UB_MAX_SHM_NAME_LENGTH];
    char primary_shm_name[UB_MAX_SHM_NAME_LENGTH];
    errno_t rc = snprintf_s(local_shm_name, sizeof(local_shm_name), sizeof(local_shm_name) - 1,
                        "ub_node%02d_%s_txn_cache", SS_MY_INST_ID, user_name);
    securec_check_ss_c(rc, "\0", "\0");
    rc = snprintf_s(primary_shm_name, sizeof(primary_shm_name), sizeof(primary_shm_name) - 1,
                        "ub_node%02d_%s_txn_cache", SS_PRIMARY_ID, user_name);
    securec_check_ss_c(rc, "\0", "\0");

    ereport(LOG, (errmsg("[UB DEBUG] Local node=%d, Primary node=%d", SS_MY_INST_ID, SS_PRIMARY_ID)));
    ereport(LOG, (errmsg("[UB DEBUG] Local shm_name=%s, Primary shm_name=%s", local_shm_name, primary_shm_name)));

    if (!UBSMemAllocate(local_shm_name, sz.total_size)) {
        return false;
    }

    void *local_addr = nullptr;
    int ret = ubsmem_shmem_map(nullptr, sz.total_size, PROT_READ | PROT_WRITE,
                               MAP_SHARED, local_shm_name, 0, &local_addr);
    if (ret != UBSM_OK || local_addr == nullptr) {
        ereport(ERROR, (errmsg("Failed to map UB shared memory: %d, local_shm_name=%s", ret, local_shm_name)));
        return false;
    }

    ereport(LOG, (errmsg("[UB DEBUG] ubsmem_shmem_map success: addr=%p", local_addr)));

    UBShmControlBlock *ctrl = (UBShmControlBlock *)local_addr;
    bool new_created = (ctrl->total_size.load(std::memory_order_relaxed) == 0);
    if (new_created) {
        InitUBSMemControlBlock(ctrl, sz.total_size, sz.clog_size, sz.csnlog_size, sz.xmin_size, sz.snapshot_size);
    } else {
        if (!UBSMemVerification((char *)local_addr)) {
            ereport(LOG, (errmsg("UB shared memory verification failed, reinitializing control block")));
            InitUBSMemControlBlock(ctrl, sz.total_size, sz.clog_size, sz.csnlog_size, sz.xmin_size, sz.snapshot_size);
        }
    }

    InitUBSMemBuffer(ctrl, (char *)local_addr);

    ret = ubsmem_shmem_unmap(local_addr, sz.total_size);
    if (ret != UBSM_OK) {
        ereport(WARNING, (errmsg("Failed to unmap local UB shared memory: %d", ret)));
    }

    ereport(LOG, (errmsg("[UB DEBUG] ubsmem_shmem_map: name=%s, size=%lu", primary_shm_name, sz.total_size)));

    void *addr = nullptr;
    ret = ubsmem_shmem_map(nullptr, sz.total_size, PROT_READ | PROT_WRITE,
                           MAP_SHARED, primary_shm_name, 0, &addr);
    if (ret != UBSM_OK || addr == nullptr) {
        ereport(ERROR, (errmsg("Failed to map UB shared memory: %d, primary_shm_name=%s", ret, primary_shm_name)));
        return false;
    }

    ereport(LOG, (errmsg("[UB DEBUG] ubsmem_shmem_map success: addr=%p", addr)));

    g_instance.shmem_cxt.UBTxnCachePtr = (char *)addr;

    ereport(LOG, (errmsg("UB shared memory initialized (size: %lu, %s)",
                         sz.total_size, new_created ? "new create" : "reused")));
    ereport(LOG, (errmsg("[UB DEBUG] UBTxnCachePtr=%p", addr)));
    return true;
}

bool UBSMemFinalize()
{
    char *addr = g_instance.shmem_cxt.UBTxnCachePtr;
    if (addr != nullptr) {
        UBShmControlBlock *ctrl = (UBShmControlBlock *)addr;
        size_t length = (size_t)ctrl->total_size.load(std::memory_order_acquire);
        int ret = ubsmem_shmem_unmap((void*)addr, length);
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
                             "total_size: %lu, clog: [%lu, %lu], csnlog: [%lu, %lu], "
                             "oldest_xmin: [%lu, %lu], snapshot: [%lu, %lu]",
                             total_size, clog_offset, clog_size, csnlog_offset, csnlog_size,
                             oldest_xmin_offset, oldest_xmin_size, snapshot_offset, snapshot_size)));
    }

    return valid;
}

static bool UBSBufferSafeMemcpy(char *dest, const char *src, size_t size)
{
    const size_t CHUNK_SIZE = 1024 * 1024 * 1024;
    size_t offset = 0;
    
    while (offset < size) {
        size_t chunk = (size - offset) < CHUNK_SIZE ? (size - offset) : CHUNK_SIZE;
        errno_t rc = memcpy_s(dest + offset, chunk, src + offset, chunk);
        securec_check_c(rc, "\0", "\0");
        offset += chunk;
    }
    return true;
}

bool UBSMemSyncFromOldPrimary(int32 old_primary_id, int32 new_primary_id)
{
    struct timeval start_time;
    gettimeofday(&start_time, NULL);

    if (old_primary_id < 0 || old_primary_id >= DMS_MAX_INSTANCE) {
        ereport(ERROR, (errmsg("Invalid old primary ID: %d", old_primary_id)));
        return false;
    }
    
    if (new_primary_id < 0 || new_primary_id >= DMS_MAX_INSTANCE) {
        ereport(ERROR, (errmsg("Invalid new primary ID: %d", new_primary_id)));
        return false;
    }
    
    if (old_primary_id == new_primary_id) {
        ereport(ERROR, (errmsg("Old primary ID equals new primary ID: %d", old_primary_id)));
        return false;
    }
    
    char old_shm_name[UB_MAX_SHM_NAME_LENGTH];
    char new_shm_name[UB_MAX_SHM_NAME_LENGTH];
    
    if (!GetUBSMemName(old_primary_id, old_shm_name, sizeof(old_shm_name))) {
        return false;
    }
    
    if (!GetUBSMemName(new_primary_id, new_shm_name, sizeof(new_shm_name))) {
        return false;
    }
    
    char *old_primary_addr = nullptr;
    char *new_primary_addr = nullptr;
    size_t total_size = 0;
    
    if (g_instance.shmem_cxt.UBTxnCachePtr != nullptr) {
        old_primary_addr = g_instance.shmem_cxt.UBTxnCachePtr;
    } else {
        int map_ret = ubsmem_shmem_map(nullptr, total_size, PROT_READ | PROT_WRITE,
                                        MAP_SHARED, old_shm_name, 0, (void **)&old_primary_addr);
        if (map_ret != UBSM_OK || old_primary_addr == nullptr) {
            ereport(ERROR, (errmsg("Failed to map old primary UB shared memory: %d", map_ret)));
            return false;
        }
    }
    UBShmControlBlock *old_ctrl = (UBShmControlBlock *)old_primary_addr;
    total_size = (size_t)old_ctrl->total_size.load(std::memory_order_acquire);

    int map_ret = ubsmem_shmem_map(nullptr, total_size, PROT_READ | PROT_WRITE,
                                    MAP_SHARED, new_shm_name, 0, (void **)&new_primary_addr);
    if (map_ret == UBSM_ERR_NOT_FOUND) {
        if (!UBMemRegionInit()) {
            ereport(ERROR, (errmsg("Failed to initialize UB memory region")));
            return false;
        }
        
        if (!UBSMemAllocate(new_shm_name, total_size)) {
            ereport(ERROR, (errmsg("Failed to allocate UB shared memory for new primary")));
            return false;
        }
        
        map_ret = ubsmem_shmem_map(nullptr, total_size, PROT_READ | PROT_WRITE,
                                    MAP_SHARED, new_shm_name, 0, (void **)&new_primary_addr);
        if (map_ret != UBSM_OK || new_primary_addr == nullptr) {
            ereport(ERROR, (errmsg("Failed to map new primary UB shared memory after creation: %d", map_ret)));
            return false;
        }
    } else if (map_ret != UBSM_OK || new_primary_addr == nullptr) {
        ereport(ERROR, (errmsg("Failed to map new primary UB shared memory: %d", map_ret)));
        return false;
    }
    UBShmControlBlock *new_ctrl = (UBShmControlBlock *)new_primary_addr;

    UBShmStdSize sz = CalUBSMemSize();
    InitUBSMemControlBlock(new_ctrl, sz.total_size, sz.clog_size, sz.csnlog_size,
                          sz.xmin_size, sz.snapshot_size);
    InitUBSMemBuffer(new_ctrl, new_primary_addr);

    uint64 clog_offset = sizeof(UBShmControlBlock);
    uint64 csnlog_offset = sizeof(UBShmControlBlock) + sz.clog_size;
    char *old_clog_ptr = old_primary_addr + clog_offset;
    char *new_clog_ptr = new_primary_addr + clog_offset;
    char *old_csnlog_ptr = old_primary_addr + csnlog_offset;
    char *new_csnlog_ptr = new_primary_addr + csnlog_offset;

    size_t copied_bytes = 0;
    if (UBSMemVerification(old_primary_addr)) {
        bool memcpy_ok = true;

        if (!UBSBufferSafeMemcpy(new_clog_ptr, old_clog_ptr, sz.clog_size)) {
            struct timeval end_time;
            gettimeofday(&end_time, NULL);
            long elapsed_ms = (end_time.tv_sec - start_time.tv_sec) * 1000 +
                              (end_time.tv_usec - start_time.tv_usec) / 1000;
            ereport(WARNING, (errmsg("[UB SYNC TIMING] UBSMemSyncFromOldPrimary CLOG copy failed")));
            memcpy_ok = false;
        } else {
            copied_bytes += sz.clog_size;
        }

        if (!UBSBufferSafeMemcpy(new_csnlog_ptr, old_csnlog_ptr, sz.csnlog_size)) {
            struct timeval end_time;
            gettimeofday(&end_time, NULL);
            long elapsed_ms = (end_time.tv_sec - start_time.tv_sec) * 1000 +
                              (end_time.tv_usec - start_time.tv_usec) / 1000;
            ereport(WARNING, (errmsg("[UB SYNC TIMING] UBSMemSyncFromOldPrimary CSNLOG copy failed")));
            memcpy_ok = false;
        } else {
            copied_bytes += sz.csnlog_size;
        }

        if (memcpy_ok) {
            ereport(LOG, (errmsg("[UB SYNC] UBSMemSyncFromOldPrimary memcpy succeeded")));
        } else {
            ereport(WARNING, (errmsg("[UB SYNC] UBSMemSyncFromOldPrimary memcpy partially failed, "
                                     "using freshly initialized new primary UB shared memory")));
        }
    }

    g_instance.shmem_cxt.UBTxnCachePtr = new_primary_addr;
    UBCLogShmemInit();
    UBCSNLogShmemInit();
    UBOldestXminShmemInit();
    UBSnapshotShmemInit();
    if (old_primary_addr != g_instance.shmem_cxt.UBTxnCachePtr) {
        map_ret = ubsmem_shmem_unmap((void*)old_primary_addr, total_size);
        if (map_ret != UBSM_OK) {
            ereport(WARNING, (errmsg("Failed to unmap old primary UB memory: %d", map_ret)));
        }
    }
    
    struct timeval end_time;
    gettimeofday(&end_time, NULL);
    long elapsed_ms = (end_time.tv_sec - start_time.tv_sec) * 1000 +
                      (end_time.tv_usec - start_time.tv_usec) / 1000;
    ereport(LOG, (errmsg("[UB SYNC TIMING] UBSMemSyncFromOldPrimary SUCCESS: "
                         "old=%d, new=%d, total_size=%lu, copied=%lu bytes, elapsed_ms=%ld ms",
                         old_primary_id, new_primary_id, (unsigned long)total_size,
                         (unsigned long)copied_bytes, elapsed_ms)));
    
    return true;
}

/* USE_UB_TXN_CACHE - END */