/*
 * Copyright (c) 2024 Huawei Technologies Co.,Ltd.
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
 * -------------------------------------------------------------------------
 *
 * common_parallel.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/common_parallel.h
 *
 * -------------------------------------------------------------------------
 */
#ifndef COMMON_PARALLEL_H
#define COMMON_PARALLEL_H

#include <functional>

#include "postmaster/bgworker.h"

typedef struct CommonShared {
    int parallelWorkers;
    pg_atomic_uint32 cuThreadId;
    uint32 dataSize;
    std::function<void(int, int)> func;
};

CommonShared *CommonInitShared(const std::function<void(int, int)> &func, int parallelWorkers, int dataSize);
void CommonParallelMain(const BgWorkerContext *bwc);
void EndCommonParallel();
void BeginCommonParallel(const std::function<void(int, int)> &func, int parallelWorkers, int dataSize);
#endif