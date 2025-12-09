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
* ogai_worker.h
*
* IDENTIFICATION
*        src/include/access/datavec/ogai_worker.h
*
* ---------------------------------------------------------------------------------------
*/

#ifndef OGAIWORKER_H
#define OGAIWORKER_H

#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "access/datavec/vector.h"

#define SCAN_INTERVAL      5000000L      /* Scan queue interval (5 seconds, microseconds) */
#define MAX_OGAI_WORKERS   100

typedef struct OgaiWorkInfoData {
    Oid dbid;
} OgaiWorkInfoData;

typedef OgaiWorkInfoData *OgaiWorkInfo;

typedef struct OgaiWorkerItem {
    ThreadId pid;
    Oid dbid;
    TimestampTz createdbTime;
} OgaiWorkerItem;

/* -------------
* This main purpose of this shared memory is for the undo launcher and
* undo worker to communicate.
*
* ogai_launcher_pid   - Thread Id of the Ogai launcher
* rollback_request    - Current rollback request that needs to be picked up
* by an Undo worker
* active_undo_workers - Current active Undo workers. The launcher cannot launch
* a new undo worker if active_undo_workers is maxed out.
*
* -------------
*/
typedef struct OgaiWorkerShmemStruct {
    /* Latch used by backends to wake the undo launcher when it has work to do */
    Latch latch;

    ThreadId ogai_launcher_pid;
    OgaiWorkInfo createdb_request;
    uint32 active_ogai_workers;
    Oid target_dbs[MAX_OGAI_WORKERS];
    OgaiWorkerItem ogai_worker_status[MAX_OGAI_WORKERS];
} OgaiWorkerShmemStruct;


#ifdef EXEC_BACKEND
extern void OgaiLauncherMain();
extern void OgaiWorkerMain();
#endif

bool IsOgaiWorkerProcess(void);

/* shared memory specific */
extern Size OgaiWorkerShmemSize(void);
extern void OgaiWorkerShmemInit(void);

#endif
