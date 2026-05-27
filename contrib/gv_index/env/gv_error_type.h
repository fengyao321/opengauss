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
 * gv_error_type.h
 *
 * Portions Copyright (c) 2026, Huawei Technologies Co.,Ltd.
 * Portions Copyright (c) 2020, AWS
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *        contrib/gv_index/env/gv_error_type.h
 *
 * --------------------------------------------------------------------------------------
 */

#ifndef GVGRAPH_ERROR_TYPE_H
#define GVGRAPH_ERROR_TYPE_H

#include "miscadmin.h"
#include "securec.h"
#include "lite/utils/error_type.h"

namespace gs_vector {

template <annlite::ErrorType et>
struct GaussErrorMeta {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etAssertionFailure> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etUnexpectedError> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etPrintToLog> {
    static constexpr int level = LOG;
};

template <>
struct GaussErrorMeta<annlite::etPrintToScreen> {
    static constexpr int level = NOTICE;
};

template <>
struct GaussErrorMeta<annlite::etThreadNotEnough> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etNoRoutingVector> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etNoBuildingVector> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etFeatureNeedsLVQ> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etFeatureNeedsPQ> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etSimdNotSupport> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etAdvancedFeatureNotSupport> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etQuantizationTypeUnrecognized> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etFeatureNeedsQuantization> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etNoDataForPQ> {
    static constexpr int level = WARNING;
};

template <>
struct GaussErrorMeta<annlite::etNoDataForMergeGraph> {
    static constexpr int level = LOG;
};

template <>
struct GaussErrorMeta<annlite::etNotSupportedOnDiskBuilderOnly> {
    static constexpr int level = WARNING;
};

template <>
struct GaussErrorMeta<annlite::etScalarExceedsBound> {
    static constexpr int level = ERROR;
};

template <>
struct GaussErrorMeta<annlite::etPruneAlgUnrecognized> {
    static constexpr int level = ERROR;
};

} /* gs_vector */

#endif /* GVGRAPH_ERROR_TYPE_H */
