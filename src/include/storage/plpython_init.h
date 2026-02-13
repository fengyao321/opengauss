/*---------------------------------------------------------------------------------------
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
 *---------------------------------------------------------------------------------------
 * pl_package.h
 *     Definition init processes.
 * IDENTIFICATION
 *     src/include/storage/plpython_init.h
 *---------------------------------------------------------------------------------------
 */
#ifndef PLPYTHON_INIT_H_
#define PLPYTHON_INIT_H_
#include "postgres.h"

/* forward declarations */
struct PlyGlobalsCtx;
struct PlySessionCtx;

typedef struct PlPythonState
{
    bool is_init;
    /* Record the session that the current lock is granted to */
    uint64 granted_session_id;
    /* Callback function to clean up session memory */
    void (*release_PlySessionCtx_callback) (PlySessionCtx* ctx);
    struct PlyGlobalsCtx* PlyGlobalsCtx;
} PlPythonState;

extern PlPythonState* plpython_state;

extern Size PlpythonShmemSize(void);
extern void PlpythonShmemInit(void);
extern void PlPyGilAcquire(void);

#endif /* PLPYTHON_INIT_H_ */
