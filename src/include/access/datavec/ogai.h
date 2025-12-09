/*
 * Copyright (c) 2025 Huawei Technologies Co.,Ltd.
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
 * ogai.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai.h
 *
 * -------------------------------------------------------------------------
 */

#ifndef OGAI_H
#define OGAI_H

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "access/datavec/vector.h"

Datum ogai_embedding(PG_FUNCTION_ARGS);
Datum ogai_generate(PG_FUNCTION_ARGS);
Datum ogai_rerank(PG_FUNCTION_ARGS);
Datum ogai_chunk(PG_FUNCTION_ARGS);
Datum ogai_notify(PG_FUNCTION_ARGS);
#endif
