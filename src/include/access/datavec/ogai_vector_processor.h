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
 * ---------------------------------------------------------------------------------------
 *
 * ogai_vector_processor.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_vector_processor.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OGAI_VECTOR_PROCESSOR_H
#define OGAI_VECTOR_PROCESSOR_H

#include "utils/numeric.h"
#include "utils/builtins.h"
#include "fmgr.h"

// Maximum number of retries
#define VECTOR_PROCESSOR_MAX_RETRY_COUNT 3

/**
 * @brief Initialize the vector processor (sets up SPI connection, checks dependent tables, etc.)
 * @return true if initialization succeeds; false if it fails (failure reason will be logged)
 */
bool ogaiVectorProcessorInit();

/**
 * @brief Scan and process the vectorization queue (core business logic)
 * @note Each call processes up to 10 pending tasks to avoid blocking the worker thread.
 * @return void (errors are logged internally and do not propagate as exceptions,
 *              ensuring worker thread stability)
 */
void OgaiVectorProcessorScanAndProcess();

/**
 * @brief Destroy the vector processor (releases SPI resources, etc.)
 * @return void
 */
void OgaiVectorProcessorDestroy();

#endif // OGAI_VECTOR_PROCESSOR_H