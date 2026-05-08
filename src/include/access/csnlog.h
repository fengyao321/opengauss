/* ---------------------------------------------------------------------------------------
 * 
 * csnlog.h
 *        Commit-Sequence-Number log.
 * 
 * Portions Copyright (c) 1996-2014, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 * 
 * IDENTIFICATION
 *        src/include/access/csnlog.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef CSNLOG_H
#define CSNLOG_H

#include "access/xlog.h"
#include <atomic>

#define CSNBufHashPartition(hashcode) ((hashcode) % NUM_CSNLOG_PARTITIONS)

#define CSNLOGDIR (g_instance.datadir_cxt.csnlogDir)

extern void CSNLogSetCommitSeqNo(TransactionId xid, int nsubxids, TransactionId* subxids, CommitSeqNo csn);
extern CommitSeqNo CSNLogGetCommitSeqNo(TransactionId xid);
extern CommitSeqNo CSNLogGetNestCommitSeqNo(TransactionId xid);
extern CommitSeqNo CSNLogGetDRCommitSeqNo(TransactionId xid);

extern Size CSNLOGShmemBuffers(void);
extern Size CSNLOGShmemSize(void);
extern void CSNLOGShmemInit(void);
extern void BootStrapCSNLOG(void);
extern void StartupCSNLOG();
extern void ShutdownCSNLOG(void);
extern void CheckPointCSNLOG(void);
extern void ExtendCSNLOG(TransactionId newestXact);
extern void TruncateCSNLOG(TransactionId oldestXact);
void SSCSNLOGShmemClear(void);

/* USE_UB_TXN_CACHE - BEGIN */

#define UB_CSNLOG_BUFFER_SLOTS (1ULL << 27)
#define UB_CSNLOG_MAX_TIMELINE ((1ULL << 37) - 1)  // timeline 最大值 (64-27=37 bits)
#define UB_CSNLOG_CAL_SLOT_INDEX(xid) ((xid) % UB_CSNLOG_BUFFER_SLOTS)
#define UB_CSNLOG_EXPECTED_TIMELINE(xid) ((xid) / UB_CSNLOG_BUFFER_SLOTS)
#define UB_CSNLOG_SHM_NAME "UB_CSNLOG_BUFFER"

typedef std::atomic<__uint128_t> UBCSNLogBufferSlot;

#define UB_CSNLOG_PACK_SLOT(timelineid, csn) \
    (((__uint128_t)(timelineid) << 64) | (__uint128_t)(csn))

#define UB_CSNLOG_UNPACK_TIMELINEID(slot_val) ((uint64)((slot_val) >> 64))
#define UB_CSNLOG_UNPACK_CSN(slot_val) ((uint64)((slot_val) & (((__uint128_t)1 << 64) - 1)))

static inline bool UBCSNLogIsValidXid(TransactionId xid) {
    return UB_CSNLOG_EXPECTED_TIMELINE(xid) <= UB_CSNLOG_MAX_TIMELINE;
}

typedef struct {
    UBCSNLogBufferSlot slots[UB_CSNLOG_BUFFER_SLOTS];
} UBCSNLogBuffer;

extern void UBCSNLogBufferInit(UBCSNLogBuffer *buf);
extern void UBCSNLogBufferSetSlot(UBCSNLogBuffer *buf, TransactionId xid, uint64 csn);
extern Size UBCSNLogBufferSize(void);
extern void UBCSNLogShmemInit(void);
extern bool UBGetCSNFromPrimary(TransactionId xid, uint64 *csn);

/* USE_UB_TXN_CACHE - END */

#endif /* CSNLOG_H */
