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
 * gv_event_handler_impl.h
 *  event handler implementation for gv index
 * 
 * 
 * IDENTIFICATION
 *        contrib/gv_index/env/gv_event_handler_impl.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef GVGRAPH_EVENT_HANDLER_IMPL_H
#define GVGRAPH_EVENT_HANDLER_IMPL_H

#include "c.h"
#include "utils/elog.h"

#include "gv_error_type.h"
#include "lite/index/light_env/event_handler.h"

namespace gs_vector {

struct GVEventHandlerImpl : public annlite::light_env::EventHandler {
    void error_throw(annlite::ErrorType type, const char *msg, size_t size) override
    {
        switch (type) {
            case annlite::etAssertionFailure:
                error_throw_internal<annlite::etAssertionFailure>(msg, size);
                return;
            case annlite::etUnexpectedError:
                error_throw_internal<annlite::etUnexpectedError>(msg, size);
                return;
            case annlite::etThreadNotEnough:
                error_throw_internal<annlite::etThreadNotEnough>(msg, size);
                return;
            case annlite::etNoRoutingVector:
                error_throw_internal<annlite::etNoRoutingVector>(msg, size);
                return;
            case annlite::etNoBuildingVector:
                error_throw_internal<annlite::etNoBuildingVector>(msg, size);
                return;
            case annlite::etFeatureNeedsLVQ:
                error_throw_internal<annlite::etFeatureNeedsLVQ>(msg, size);
                return;
            case annlite::etFeatureNeedsPQ:
                error_throw_internal<annlite::etFeatureNeedsPQ>(msg, size);
                return;
            case annlite::etSimdNotSupport:
                error_throw_internal<annlite::etSimdNotSupport>(msg, size);
                return;
            case annlite::etAdvancedFeatureNotSupport:
                error_throw_internal<annlite::etAdvancedFeatureNotSupport>(msg, size);
                return;
            case annlite::etQuantizationTypeUnrecognized:
                error_throw_internal<annlite::etQuantizationTypeUnrecognized>(msg, size);
                return;
            case annlite::etFeatureNeedsQuantization:
                error_throw_internal<annlite::etFeatureNeedsQuantization>(msg, size);
                return;
            case annlite::etNoDataForPQ:
                error_throw_internal<annlite::etNoDataForPQ>(msg, size);
                return;
            case annlite::etNoDataForMergeGraph:
                error_throw_internal<annlite::etNoDataForMergeGraph>(msg, size);
                return;
            case annlite::etNotSupportedOnDiskBuilderOnly:
                error_throw_internal<annlite::etNotSupportedOnDiskBuilderOnly>(msg, size);
                return;
            case annlite::etScalarExceedsBound:
                error_throw_internal<annlite::etScalarExceedsBound>(msg, size);
                return;
            default:
                error_throw_internal<annlite::etUnexpectedError>("unknown error type.");
        }
    }

    void log(const char* msg) override
    {
        ereport(NOTICE, (errmsg("%s", msg)));
    }

    bool is_interrupted() override
    {
        return InterruptPending;
    }
private:
    // throw msg
    template <annlite::ErrorType et, typename... Args>
    static void error_throw_internal(const char* msg, size_t bytes = 0)
    {
        ereport(GaussErrorMeta<et>::level, (errmodule(MOD_INDEX), errmsg("%s", msg)));
    }
};

} // namespace gs_vector

#endif /* GV_EVENT_HANDLER_IMPL_H */