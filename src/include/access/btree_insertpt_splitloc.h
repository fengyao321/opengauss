/* -------------------------------------------------------------------------
 *
 * btree_insertpt_splitloc.h
 *    Shared insert-position-aware btree split candidate collection and
 *    split-point selection (used by ubtree, nbtree insertpt path, ubtree PCR).
 *
 * Portions Copyright (c) 2024 Huawei Technologies Co.,Ltd.
 *
 * IDENTIFICATION
 *    src/include/access/btree_insertpt_splitloc.h
 *
 * -------------------------------------------------------------------------
 */
#ifndef BTREE_INSERTPT_SPLITLOC_H
#define BTREE_INSERTPT_SPLITLOC_H

#include "postgres.h"
#include "access/itup.h"

/* Split-interval limits (default strategy); see "Prefix B-Trees" discussion */
#define BTREE_INSERTPT_MAX_LEAF_INTERVAL 9
#define BTREE_INSERTPT_MAX_INTERNAL_INTERVAL 18

typedef enum BTreeInsertptFindStrat {
    BTREE_INSERTPT_SPLIT_DEFAULT = 0,
    BTREE_INSERTPT_SPLIT_MANY_DUPLICATES,
    BTREE_INSERTPT_SPLIT_SINGLE_VALUE
} BTreeInsertptFindStrat;

typedef struct BTreeInsertptSplitPoint {
    int16 curdelta;
    int16 leftfree;
    int16 rightfree;
    OffsetNumber firstoldonright;
    bool newitemonleft;
} BTreeInsertptSplitPoint;

typedef struct BTreeInsertptFindSplitData {
    Relation rel;
    Page page;
    IndexTuple newitem;
    Size newitemsz;
    bool is_leaf;
    bool is_rightmost;
    OffsetNumber newitemoff;
    int leftspace;
    int rightspace;
    int olddataitemstotal;
    Size minfirstrightsz;
    int maxsplits;
    int nsplits;
    BTreeInsertptSplitPoint *splits;
    int interval;
} BTreeInsertptFindSplitData;

typedef Size (*BTreeInsertptItemSizeFn)(Page page, OffsetNumber offnum, void *ctx);

typedef struct BTreeInsertptSplitOps {
    bool (*after_newitemoff)(BTreeInsertptFindSplitData *state, OffsetNumber maxoff, int leaffillfactor,
        bool *usemult);
    IndexTuple (*split_last_left)(BTreeInsertptFindSplitData *state, BTreeInsertptSplitPoint *split);
    IndexTuple (*split_first_right)(BTreeInsertptFindSplitData *state, BTreeInsertptSplitPoint *split);
    IndexTuple (*get_hikey_tuple)(Page page);
    int (*split_penalty)(BTreeInsertptFindSplitData *state, BTreeInsertptSplitPoint *split);
} BTreeInsertptSplitOps;

extern void BTreeInsertptRecsplitloc(BTreeInsertptFindSplitData *state, OffsetNumber firstoldonright,
    bool newitemonleft, int olddataitemstoleft, Size firstoldonrightsz, Size lineptr_sz,
    bool internal_tuple_minus_txn);

extern void BTreeInsertptCollectSplitCandidates(BTreeInsertptFindSplitData *state,
    OffsetNumber firstdatakey, OffsetNumber maxoff, OffsetNumber newitemoff, BTreeInsertptItemSizeFn item_size_fn,
    void *item_ctx, Size lineptr_sz, bool internal_tuple_minus_txn);

extern bool BTreeInsertptAdjacentHeapTid(ItemPointer lowhtid, ItemPointer highhtid);

extern void BTreeInsertptDeltasortsplits(BTreeInsertptFindSplitData *state, double fillfactormult, bool usemult);

extern void BTreeInsertptIntervalEdges(const BTreeInsertptFindSplitData *state,
    BTreeInsertptSplitPoint **leftinterval, BTreeInsertptSplitPoint **rightinterval);

extern int BTreeInsertptStrategy(BTreeInsertptFindSplitData *state, BTreeInsertptSplitPoint *leftpage,
    BTreeInsertptSplitPoint *rightpage, BTreeInsertptFindStrat *strategy, const BTreeInsertptSplitOps *ops);

extern OffsetNumber BTreeInsertptBestsplitloc(BTreeInsertptFindSplitData *state, int perfectpenalty,
    bool *newitemonleft, BTreeInsertptFindStrat strategy, const BTreeInsertptSplitOps *ops);

extern OffsetNumber BTreeInsertptFinishChooseSplitLocation(BTreeInsertptFindSplitData *state, BlockNumber blkno,
    OffsetNumber maxoff, OffsetNumber newitemoff, int leaffillfactor, bool *newitemonleft,
    const BTreeInsertptSplitOps *ops);

#endif /* BTREE_INSERTPT_SPLITLOC_H */
