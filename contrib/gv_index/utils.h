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
 * utils.h
 *
 * Portions Copyright (c) 2026, Huawei Technologies Co.,Ltd.
 * Portions Copyright (c) 2020, AWS
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *        contrib/gv_index/utils.h
 *
 * --------------------------------------------------------------------------------------
 */

#ifndef GV_GRAPH_UTILS_H
#define GV_GRAPH_UTILS_H

#include <cinttypes>
#include <cstdio>
#include "c.h"
#include "access/htup.h"
#include "access/itup.h"
#include "access/reloptions.h"
#include "access/relscan.h"
#include "access/sdir.h"
#include "storage/buf/block.h"
#include "storage/off.h"
#include "storage/procarray.h"
#include "utils/elog.h"
#include "utils/relcache.h"
#include "utils/snapmgr.h"

#include "graph_values.h"
#include "lite/subindex/dist_metric/vector_distance_type.h"

#define FAST_NOTICE(fmt, ...) ereport(NOTICE, (errmsg(fmt, ##__VA_ARGS__)))
#define VECTOR_INDEX_TUPLE_GET_XID(itup) (VectorIndexXid)(((char*)(itup)) + (IndexTupleSize(itup)))

enum VectorIndexDmlType {
    VECTOR_DML_INSERT,
    VECTOR_BUILD_INDEX_INSERT,
    VECTOR_DML_DELETE
};

static inline bool vector_item_id_is_dead(const ItemIdData* item_id)
{
    return item_id->lp_flags == LP_DEAD;
}

static inline void vector_set_xmin_xmax(VectorIndexXid vxid, VectorIndexDmlType dml_type, TransactionId xid)
{
    if (dml_type == VECTOR_DML_INSERT) {
        vxid->xmin = GetCurrentTransactionId();
        vxid->xmax = InvalidTransactionId;
    }
    if (dml_type == VECTOR_BUILD_INDEX_INSERT) {
        vxid->xmin = FrozenTransactionId;
        vxid->xmax = InvalidTransactionId;
    }
    if (dml_type == VECTOR_DML_DELETE) {
        vxid->xmax = GetCurrentTransactionId();
    }
}

/*
 * 从 pg_class syscache 读取索引的原始 reloptions datum。
 */
extern Datum get_index_reloptions_datum(Oid indexId);

/*
 * 从索引的 opfamily 名称推断距离类型（L2 或 Cosine）。
 */
extern annlite::VectorDistanceType get_distance_type_from_index(Relation index);

bool gv_graph_tuple_equal(IndexTuple itup1, IndexTuple itup2);

TransactionIdStatus gv_graph_check_xid(TransactionId xid);

bool gv_graph_get_tuple_xmin_xmax(Page page, OffsetNumber offnum, TransactionId oldest_xmin, TransactionId *xmin,
                        TransactionId *xmax, bool *xminCommitted, bool *xmaxCommitted, bool isToast);

bool vector_get_tuple_xmin_xmax_simple(const IndexTupleDataWithTransInfo& transInfo, TransactionId oldest_xmin,
        TransactionId *xmin, TransactionId *xmax, bool *xmin_committed, bool *xmax_committed, int2 bucketid);

IndexTupleData* vector_check_keys_simple(IndexScanDesc scan, const IndexTupleDataWithTransInfo& transInfo,
    ScanDirection dir, bool *need_recheck, bool is_alive);

void gv_graph_index_init(void);

void register_graph_reloptions(relopt_kind kind);

void gv_graph_xlog_write_page(Relation rel, BlockNumber nblocks);
                    

#endif /* GV_GRAPH_UTILS_H */