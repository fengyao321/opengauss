/* -------------------------------------------------------------------------
 *
 * bridge.h
 *    Header file for openGauss Ustore Bridge Index subsystem.
 *
 * Portions Copyright (c) 2026, openGauss Contributors
 *
 * IDENTIFICATION
 *    src/include/access/bridge.h
 *
 * -------------------------------------------------------------------------
 */

#ifndef BRIDGE_INDEX_H
#define BRIDGE_INDEX_H

#include "postgres.h"
#include "access/relscan.h"
#include "access/skey.h"
#include "catalog/pg_am.h"
#include "nodes/pg_list.h"
#include "storage/item/itemptr.h"
#include "storage/lock/lock.h"
#include "utils/rel.h"

/* 48-bit monotonic sequence number for bridge_ctid */
typedef uint64 BridgeSeqNo;

#define BRIDGE_INVALID_SEQ ((BridgeSeqNo)0)
#define BRIDGE_FIRST_SEQ   ((BridgeSeqNo)1)

/* Convert a 48-bit bridge sequence number into a 6-byte ItemPointerData */
static inline ItemPointerData BridgeSeqToItemPointer(BridgeSeqNo seq)
{
    ItemPointerData itemptr;
    BlockNumber blkno = (BlockNumber)(seq >> 16);
    OffsetNumber offno = (OffsetNumber)((seq & 0xFFFF) + 1);
    ItemPointerSet(&itemptr, blkno, offno);
    return itemptr;
}

/* Convert a 6-byte ItemPointerData back into a 48-bit bridge sequence number */
static inline BridgeSeqNo ItemPointerToBridgeSeq(const ItemPointer itemptr)
{
    BlockNumber blkno = ItemPointerGetBlockNumber(itemptr);
    OffsetNumber offno = ItemPointerGetOffsetNumber(itemptr);
    return (((BridgeSeqNo)blkno) << 16) | (BridgeSeqNo)(offno - 1);
}

/*
 * Check if the given access method is supported via Bridge on Ustore
 * For Phase 1: Hash and GiST
 */
static inline bool IndexAmIsBridged(Oid amOid)
{
    return (amOid == HASH_AM_OID || amOid == GIST_AM_OID);
}

/*
 * Check if the given relation is a bridged index on Ustore
 */
static inline bool RelationIsBridgedIndex(Relation rel)
{
    if (rel == NULL || rel->rd_rel == NULL) {
        return false;
    }
    if (rel->rd_rel->relkind != RELKIND_INDEX) {
        return false;
    }
    if (rel->rd_tam_ops != TableAmUstore) {
        return false;
    }
    return IndexAmIsBridged(rel->rd_rel->relam);
}

/* Core Bridge subsystem APIs */
extern BridgeSeqNo BridgeGetNextSeq(Oid heapRelId);
extern Relation BridgeGetOrCreateRelation(Relation heapRel, LOCKMODE lockmode);
extern Relation BridgeGetRelation(Relation heapRel, LOCKMODE lockmode);
extern Relation BridgeGetSeqIndexRelation(Relation heapRel, LOCKMODE lockmode);
extern Relation BridgeGetTidIndexRelation(Relation heapRel, LOCKMODE lockmode);
extern Oid BridgeGetRelationOid(Relation heapRel);
extern bool BridgeInsertEntry(Relation heapRel, Relation indexRel, ItemPointer physicalTid, ItemPointer bridgeTidOut);
extern bool BridgeDeleteEntry(Relation indexRel, Datum* values, const bool* isnull, ItemPointer physicalTid, bool isRollback);
extern bool BridgeLookupAndVerifyVisibility(Relation bridgeRel, Relation bridgeIdx, BridgeSeqNo seq, Snapshot snapshot, ItemPointer physicalTid);

#endif /* BRIDGE_INDEX_H */

