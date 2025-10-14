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
 * rack_mem_cleaner.h
 *        Exports from postmaster/rack_mem_cleaner.c.
 *
 *
 * IDENTIFICATION
 *       src/include/postmaster/rack_mem_cleaner.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OPENGAUSS_RACK_MEM_CLEANER_H
#define OPENGAUSS_RACK_MEM_CLEANER_H

#include <pthread.h>
#include <unistd.h>
#include "postgres.h"

#define HIGH_PROCMEM_MARK 80
constexpr int kilobytes = 1024;
constexpr uint64 MAX_RACK_MEMORY_LIMIT = 32 * 1024 * 1024;

// memory block structure
using RackMemControlBlock = struct RackMemControlBlock {
    void *ptr;
    int tryCount;
    struct RackMemControlBlock *next;
    Size size;
};

using knl_g_rack_mem_cleaner_context = struct KnlGRackMemCleanerContext {
    pthread_mutex_t mutex;
    pthread_cond_t cond;

    // memory queue status
    RackMemControlBlock *queueHead;
    size_t queueSize;

    uint64_t total;
    uint64_t freeCount;
    volatile uint64_t countToProcess;

    // mem
    MemoryContext memoryContext;

    // control flag
    volatile int cleanupActive;
    volatile uint32_t rack_available;
};

extern void RackMemCleanerMain(void);
extern void RegisterFailedFreeMemory(void *ptr, Size size);
#endif  // OPENGAUSS_RACK_MEM_CLEANER_H