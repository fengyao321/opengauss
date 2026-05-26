/*
 * Copyright (c) 2026 Huawei Technologies Co.,Ltd.
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
 * pg_init.h
 *  init function for gv index
 * 
 * 
 * IDENTIFICATION
 *        contrib/gv_index/pg_init.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef GV_PG_INIT_H
#define GV_PG_INIT_H

#include "access/reloptions.h"

/* 通过 add_reloption_kind() 动态分配，在gv_graph_index_handler.cpp 中使用 */
extern relopt_kind gv_graph_kind_id;
extern void gv_graph_index_init();

#endif /* GV_PG_INIT_H */