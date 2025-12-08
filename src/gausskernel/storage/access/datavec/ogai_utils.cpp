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
 * ogai_utils.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/storage/access/datavec/ogai_utils.cpp
 *
 * ---------------------------------------------------------------------------------------
 */

#include "postgres.h"
#include "keymgr/comm/security_error.h"
#include "access/datavec/ogai_utils.h"

HttpMgr* GetHttpMgr(KmErr* errBuf, const char* url, const char* apiKey)
{
    HttpMgr* httpMgr = NULL;
    /* remain resbody */
    char remain[3] = {0, 0, 1};

    httpMgr = httpmgr_new(errBuf);
    if (httpMgr == NULL) {
        km_err_free(errBuf);
        elog(ERROR, "new ogai http client failed.");
        return NULL;
    }
    httpmgr_set_req_line(httpMgr, url, CURLOPT_POST, NULL);
    if (apiKey) {
        int authLen = strlen("Authorization: Bearer ") + strlen(apiKey) + 1;
        char* auth = (char *)km_alloc(authLen);
        if (auth == NULL) {
            elog(ERROR, "malloc memory error");
            return NULL;
        }
        errno_t rc = sprintf_s(auth, authLen, "Authorization: Bearer %s", apiKey);
        km_securec_check_ss(rc, "", "");
        httpmgr_set_req_header(httpMgr, auth);
    }
    httpmgr_set_req_header(httpMgr, "Content-Type:application/json");
    httpmgr_set_response(httpMgr, remain, NULL);
    return httpMgr;
}
