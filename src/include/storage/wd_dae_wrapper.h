/* SPDX-License-Identifier: Apache-2.0 */
/*
 * Copyright 2024 Huawei Technologies Co.,Ltd. All rights reserved.
 *
 * UADK DAE Types Wrapper for openGauss
 */

#ifndef WD_DAE_WRAPPER_H
#define WD_DAE_WRAPPER_H

#include <dlfcn.h>
#include <stdbool.h>
#include <asm/types.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Define handle_t if not already defined */
#ifndef handle_t
#define handle_t uintptr_t
#endif

/**
 * wd_dae_data_type - Data type of DAE
 */
enum wd_dae_data_type {
    WD_DAE_DATE,
    WD_DAE_INT,
    WD_DAE_LONG,
    WD_DAE_SHORT_DECIMAL,
    WD_DAE_LONG_DECIMAL,
    WD_DAE_CHAR,
    WD_DAE_VARCHAR,
    WD_DAE_DATA_TYPE_MAX,
};

/**
 * wd_dae_charset - Charset information of DAE
 */
struct wd_dae_charset {
    bool binary_format;
    bool space;
    bool subwoofer;
};

/**
 * wd_dae_col_addr - Column information of DAE.
 */
struct wd_dae_col_addr {
    __u8 *empty;
    void *value;
    __u32 *offset;
    __u64 empty_size;
    __u64 value_size;
    __u64 offset_size;
};

/**
 * wd_dae_row_addr - information of row memory.
 */
struct wd_dae_row_addr {
    void *addr;
    __u32 row_size;
    __u32 row_num;
};

/**
 * wd_dae_hash_table - Hash table information of DAE.
 */
struct wd_dae_hash_table {
    void *std_table;
    void *ext_table;
    __u32 std_table_row_num;
    __u32 ext_table_row_num;
    __u32 table_row_size;
};

#ifdef __cplusplus
}
#endif

#endif /* WD_DAE_WRAPPER_H */

