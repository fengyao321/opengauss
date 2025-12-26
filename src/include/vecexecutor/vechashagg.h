/*
 * Copyright (c) 2020 Huawei Technologies Co.,Ltd.
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
 * 
 * vechashagg.h
 *     hash agg class and class member declare.
 * 
 * IDENTIFICATION
 *        src/include/vecexecutor/vechashagg.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef VECHASHAGG_H_
#define VECHASHAGG_H_

#include "vecexecutor/vecagg.h"
#include "storage/wd_agg_wrapper.h"

constexpr int EXT_RATIO = 4;
constexpr int HASH_TABLE_ROW_NUM = 65536;
constexpr int MAX_KEY_COLS_NUM = 16;
constexpr int MAX_AGG_COLS_NUM = 16;
constexpr int CHAR_BITS = 8;
constexpr int DEFAULT_ROW_NUM = 30000;
constexpr int MAX_CHAR_SIZE = 32;
constexpr int EXT_ROW_SIZE1 = 32;
constexpr int EXT_ROW_BYTES1 = 3;
constexpr int EXT_ROW_SIZE2 = 64;
constexpr int EXT_ROW_BYTES2 = 1;

constexpr int DPA_MAX_KEY_COLS = 9;
constexpr int DPA_MAX_INPUT_COLS = 9;
constexpr int DPA_MAX_OUTPUT_COLS = 9;
constexpr int DPA_MAX_CHAR_COL_NUM = 5;
constexpr int DPA_MAX_CHAR_SIZE = 32;
constexpr int DPA_MAX_VCHAR_SIZE = 30;

struct AggStateLog {
    bool restore;
    hashCell* lastCell;
    int lastIdx;
    int lastSeg;
};

class HashAggRunner : public BaseAggRunner {
public:
    HashAggRunner(VecAggState* runtime);
    ~HashAggRunner();

    bool ResetNecessary(VecAggState* node);

    /* Wrap allocate new hash cell and initialization */
    template <bool simple, bool sgltbl>
    void AllocHashSlot(VectorBatch* batch, int i);
    void HashTableGrowUp();

private:
    /* Different build function, if we exceed the threshold in memory row number,we need to flush to the disk.*/
    template <bool simple, bool unique_check>
    void buildAggTbl(VectorBatch* batch);

    void Build();

    VectorBatch* Probe();

    /* Hash based aggregation.*/
    VectorBatch* Run();

    /* Get the hash source.*/
    hashSource* GetHashSource();

    void BindingFp();

    template <bool expand, bool logit>
    int64 computeHashTableSize(int64 newsize);
    ScalarValue getHashValue(hashCell* hashentry);

    FORCE_INLINE uint32 get_bucket(uint32 hashvalue)
    {
        return hashvalue & (uint32)(m_hashSize - 1);
    }

    template <bool simple>
    void dyHashSlotTmp(VectorBatch* batch, int i, int hash_idx, int start_idx);

    void GetPosbyLoc(uint64 idx, int* nseg, int64* pos);

    template <bool expand, bool logit>
    void BuildHashTable(int64 oldsize);

    void Profile(char* stats, bool* can_wlm_warning_statistics);

    bool DaeSessionInit(VectorBatch* batch);
    void DaeSessionCleanup();
    bool DaeIsSessionReady();
    
    void DaeAllocHTBL(struct wd_dae_hash_table *table_, struct wd_dae_hash_table *new_table, __u32 row_size);
    void DaeFreeHTBL(struct wd_dae_hash_table *table);
    
    bool DaeCollectKeyCollInfo(struct wd_key_col_info *key_cols_info, const Oid colType, int idx, int4 typeMod);
    bool DaeCollectAggCollInfo(struct wd_agg_col_info *agg_cols_info, Oid inputColType, Oid outputColType, int idx,
        int4 typeMod, Oid aggFuncOid);
    bool DaeCreateSession(VectorBatch* batch, struct wd_agg_sess_setup &setup);
    
    bool DaeInitInputOutputMem(struct wd_agg_sess_setup *setup, VectorBatch* batch);
    bool DaeInitKeyOutputAddress(struct wd_agg_sess_setup *setup);
    bool DaeInitKeyInputAddress(struct wd_agg_sess_setup *setup, VectorBatch* batch);
    bool DaeInitAggOutputAddress(struct wd_agg_sess_setup *setup);
    bool DaeInitAggInputAddress(struct wd_agg_sess_setup *setup, VectorBatch* batch);
    void DaeFreeInputOutputMem();
    
    bool ParallelBuildKeyValue(VectorBatch* batch);
    bool ParallelBuildAggValue(VectorBatch* batch);
    void DaeParallelBuild(VectorBatch* batch);
    void DaeParallelProbe();

private:
    /* Some status log.*/
    AggStateLog m_statusLog;

    /* Hash source.*/
    hashSource* m_hashSource;

    /* Hash value  to store.*/
    ScalarValue m_hashVal[BatchMaxSize];
    int m_fileIdx;
    bool m_can_grow;        /* mark weather can grow up */
    int64 m_max_hashsize;   /* memory allowed max hashtable size */
    int64 m_grow_threshold; /* the threshold to grow up */
    double m_hashbuild_time;
    double m_hashagg_time;
    MemoryContext m_hashcell_context; /* stack context for hashcell */
    HashSegTbl* m_hashData;           /*hashagg table */
    int m_segnum;                     /* segment number */
    int m_hashseg_max;                /* max hashsize for one segment */
    int64 m_hashSize;                 /* total hash size */
    void (HashAggRunner::*m_buildFun)(VectorBatch* batch);
    int m_spill_times; /* spill time */

    enum DaeSessionState {
        DAE_SESS_UNINIT = 0,
        DAE_SESS_INITIALIZING,
        DAE_SESS_READY,
        DAE_SESS_ERROR
    };

    bool use_dpa = false;
    /* DPA session context, independent from m_hashContext */
    MemoryContext m_dpaContext = nullptr;
    DaeSessionState daeSessionState_ = DAE_SESS_UNINIT;
    handle_t daeSess_ = 0;
    struct wd_agg_req daeReq_ = {0};
    struct wd_dae_hash_table daeHashTable_ = {0};
    
    struct wd_key_col_info* daeKeyCols_ = nullptr;
    struct wd_agg_col_info* daeAggCols_ = nullptr;
    __u32 daeKeyColsNum_ = 0;
    __u32 daeAggColsNum_ = 0;
    
    /* Store original column types for output processing */
    /* Array of key column type OIDs */
    Oid* daeKeyColTypes_ = nullptr;
    /* Array of key column typeMods */
    int4* daeKeyColTypeMods_ = nullptr;
};

#endif
