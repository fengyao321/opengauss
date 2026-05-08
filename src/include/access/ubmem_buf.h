#ifndef UBMEM_BUF_H
#define UBMEM_BUF_H

/* USE_UB_TXN_CACHE - BEGIN */
#include "c.h"
#include <atomic>

#define UB_MAX_HOST_NAME_LENGTH 255
#define UB_MAX_SHM_NAME_LENGTH 256
#define UB_MAX_REGION_NAME_DESC_LENGTH 256

// #define ENTER_ESB() asm volatile("esb" ::: "memory")
#define ENTER_ESB()

typedef struct {
    std::atomic<uint64> total_size;
    std::atomic<uint64> clog_offset;
    std::atomic<uint64> clog_size;
    std::atomic<bool> clog_inited;
    std::atomic<uint64> csnlog_offset;
    std::atomic<uint64> csnlog_size;
    std::atomic<bool> csnlog_inited;
    std::atomic<uint64> oldest_xmin_offset;
    std::atomic<uint64> oldest_xmin_size;
    std::atomic<bool> oldest_xmin_inited;
    std::atomic<uint64> snapshot_offset;
    std::atomic<uint64> snapshot_size;
    std::atomic<bool> snapshot_inited;
} UBShmControlBlock;

extern void UBMemRegionName(const char *host_name, char *region_name, size_t len);
extern bool UBMemRegionInit(void);
extern bool UBSMemAllocate(const char *buffer_name, size_t buffer_size);
extern bool UBSMemLogBufferCreate(void);
extern bool UBSMemFinalize(void);
extern bool UBSMemVerification(char *ub_txn_cache_ptr);

/* USE_UB_TXN_CACHE - END */
#endif /* UBMEM_BUF_H */