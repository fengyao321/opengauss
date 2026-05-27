/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2026. All rights reserved.
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
 * --------------------------------------------------------------------------------------
 *
 * graph_values.h
 *
 * Portions Copyright (c) 2026, Huawei Technologies Co.,Ltd.
 * Portions Copyright (c) 2020, AWS
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *        contrib/gv_index/graph_values.h
 *
 * --------------------------------------------------------------------------------------
 */

#ifndef GV_GRAPH_VALUES_H
#define GV_GRAPH_VALUES_H

#include <cinttypes>
#include <cstdio>
#include "c.h"
#include "access/htup.h"
#include "access/itup.h"
#include "access/relscan.h"
#include "access/sdir.h"
#include "storage/off.h"
#include "storage/procarray.h"
#include "storage/buf/block.h"
#include "utils/elog.h"
#include "utils/relcache.h"
#include "utils/snapmgr.h"

/* Vector 索引事务信息 */
typedef struct VectorIndexXidData {
    TransactionId xmin;
    TransactionId xmax;
} VectorIndexXidData;

typedef VectorIndexXidData* VectorIndexXid;
struct IndexTupleDataWithTransInfo {
    static constexpr TransactionId invalid_xmin = MAX_START_XID;
    static constexpr TransactionId invalid_xmax = InvalidSubTransactionId;

    IndexTupleDataWithTransInfo(
        BlockNumber blkid = InvalidBlockNumber,
        OffsetNumber posid = InvalidOffsetNumber,
        uint16_t info = 0,
        TransactionId xmin = invalid_xmin,
        TransactionId xmax = invalid_xmax)
        : index_tuple(), trans_info()
    {
        BlockIdSet(&index_tuple.t_tid.ip_blkid, blkid);
        index_tuple.t_tid.ip_posid = posid;
        index_tuple.t_info = info;
        trans_info.xmin = xmin;
        trans_info.xmax = xmax;
    }

    IndexTupleDataWithTransInfo(
        const ItemPointerData& tid,
        uint16_t info = 0,
        TransactionId xmin = invalid_xmin,
        TransactionId xmax = invalid_xmax)
        : index_tuple(), trans_info()
    {
        index_tuple.t_tid = tid;
        index_tuple.t_info = info;
        trans_info.xmin = xmin;
        trans_info.xmax = xmax;
    }

    IndexTupleDataWithTransInfo(IndexTupleData* _index_tuple, const VectorIndexXidData& _trans_info)
        : index_tuple(), trans_info(_trans_info)
    {
        size_t tuplesize = MAXALIGN(IndexTupleSize(_index_tuple));
        errno_t rc = memcpy_s(
            &index_tuple, sizeof(IndexTupleData) + tuple_reserved_bytes,
            _index_tuple, tuplesize);
        securec_check(rc, "", "");
    }

    IndexTupleDataWithTransInfo(const IndexTupleDataWithTransInfo&) = default;
    ~IndexTupleDataWithTransInfo() {}

    bool tid_equal_to(const ItemPointerData& tid) const
    {
        return memcmp(&index_tuple.t_tid, &tid, sizeof(ItemPointerData)) == 0;
    }

public:
    static constexpr size_t tuple_reserved_bytes = 8;
    IndexTupleData index_tuple;
    uint8_t reserved[tuple_reserved_bytes];
    VectorIndexXidData trans_info;
};

struct GraphValueTypeV3 : public IndexTupleDataWithTransInfo {
    using IndexTupleDataWithTransInfo::IndexTupleDataWithTransInfo;
    void set_bucket_id(BlockNumber bucket_id)
    {
        m_bucket_id = bucket_id;
    }
    BlockNumber bucket_id() const
    {
        return m_bucket_id;
    }
private:
    static constexpr size_t reserved_bytes = 28;
    BlockNumber m_bucket_id = InvalidBlockNumber;
    uint8_t reserved[reserved_bytes];
};

static_assert(sizeof(IndexTupleDataWithTransInfo) == 32, "IndexTupleDataWithTransInfo must be 32 bytes");
static_assert(sizeof(GraphValueTypeV3) == 64, "GraphValueTypeV3 must be 64 bytes");

#endif /* GV_GRAPH_VALUES_H */