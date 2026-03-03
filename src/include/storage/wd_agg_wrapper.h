/* SPDX-License-Identifier: Apache-2.0 */
/*
 * Copyright 2024 Huawei Technologies Co.,Ltd. All rights reserved.
 *
 * UADK DAE AGG Wrapper for openGauss
 */

#ifndef WD_AGG_WRAPPER_H
#define WD_AGG_WRAPPER_H

#include "storage/wd_dae_wrapper.h"

#ifdef __aarch64__
#define ENABLE_UADK_AGG (g_uadkAggFunc.uadk_agg_inited)
#else
#define ENABLE_UADK_AGG false
#endif

#define DPA_MAX_PRECISION 38

constexpr auto UADK_AGG_SUCCESS = 0;
constexpr auto UADK_AGG_ERROR = -1;

/**
 * alg_task_type - Algorithm task type.
 */
enum alg_task_type {
    TASK_MIX = 0x0,
    TASK_HW,
    TASK_INSTR,
    TASK_MAX_TYPE,
};

/**
 * wd_agg_alg - Aggregation operation type.
 */
enum wd_agg_alg {
    WD_AGG_SUM,
    WD_AGG_COUNT,
    WD_AGG_MAX,
    WD_AGG_MIN,
    WD_AGG_ALG_TYPE_MAX,
};

/**
 * wd_agg_task_error_type - Aggregation task error type.
 */
enum wd_agg_task_error_type {
    WD_AGG_TASK_DONE,
    WD_AGG_IN_EPARA,
    WD_AGG_NEED_REHASH,
    WD_AGG_SUM_OVERFLOW,
    WD_AGG_INVALID_HASH_TABLE,
    WD_AGG_INVALID_VARCHAR,
    WD_AGG_PARSE_ERROR,
    WD_AGG_BUS_ERROR,
};

/**
 * wd_key_col_info - Key column information.
 */
struct wd_key_col_info {
    __u16 col_data_info;
    enum wd_dae_data_type input_data_type;
};

/**
 * wd_agg_col_info - Agg column information.
 */
struct wd_agg_col_info {
    __u32 col_alg_num;
    __u16 col_data_info;
    enum wd_dae_data_type input_data_type;
    enum wd_dae_data_type output_data_types[WD_AGG_ALG_TYPE_MAX];
    enum wd_agg_alg output_col_algs[WD_AGG_ALG_TYPE_MAX];
};

/**
 * wd_agg_sess_setup - Agg session setup information.
 */
struct wd_agg_sess_setup {
    __u32 key_cols_num;
    struct wd_key_col_info *key_cols_info;
    __u32 agg_cols_num;
    struct wd_agg_col_info *agg_cols_info;
    bool is_count_all;
    enum wd_dae_data_type count_all_data_type;
    struct wd_dae_charset charset_info;
    void *sched_param;
};

struct wd_agg_req;
typedef void *wd_alg_agg_cb_t(struct wd_agg_req *req, void *cb_param);

/**
 * wd_agg_req - Aggregation operation request.
 */
struct wd_agg_req {
    struct wd_dae_col_addr *key_cols;
    struct wd_dae_col_addr *out_key_cols;
    struct wd_dae_col_addr *agg_cols;
    struct wd_dae_col_addr *out_agg_cols;
    __u32 key_cols_num;
    __u32 out_key_cols_num;
    __u32 agg_cols_num;
    __u32 out_agg_cols_num;
    __u32 in_row_count;
    __u32 out_row_count;
    __u32 real_in_row_count;
    __u32 real_out_row_count;
    wd_alg_agg_cb_t *cb;
    void *cb_param;
    __u8 *sum_overflow_cols;
    enum wd_agg_task_error_type state;
    bool output_done;
    void *priv;
};

typedef struct UadkAggFunc {
    bool uadk_agg_inited;
    void *handle;
    int (*wd_agg_init)(char *alg, __u32 sched_type, int task_type, void *ctx_params);
    void (*wd_agg_uninit)(void);
    handle_t (*wd_agg_alloc_sess)(struct wd_agg_sess_setup *setup);
    void (*wd_agg_free_sess)(handle_t h_sess);
    int (*wd_agg_set_hash_table)(handle_t h_sess, struct wd_dae_hash_table *info);
    int (*wd_agg_add_input_sync)(handle_t h_sess, struct wd_agg_req *req);
    int (*wd_agg_get_output_sync)(handle_t h_sess, struct wd_agg_req *req);
    int (*wd_agg_get_table_rowsize)(handle_t h_sess);
} UadkAggFunc;

extern UadkAggFunc g_uadkAggFunc;

extern void UadkAggFuncInit(char* wdDaePath);
extern void UadkAggFuncUnInit();

int UadkAggInit(char *alg, __u32 sched_type, int task_type, void *ctx_params);
void UadkAggUnInit();
handle_t UadkAggAllocSess(struct wd_agg_sess_setup *setup);
void UadkAggFreeSess(handle_t h_sess);
int UadkAggSetHashTable(handle_t h_sess, struct wd_dae_hash_table *info);
int UadkAggAddInputSync(handle_t h_sess, struct wd_agg_req *req);
int UadkAggGetOutputSync(handle_t h_sess, struct wd_agg_req *req);
int UadkAggGetTableRowsize(handle_t h_sess);

#endif // WD_AGG_WRAPPER_H

