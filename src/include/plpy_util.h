/*-------------------------------------------------------------------------------------
 *  Copyright (c) 2020 Huawei Technologies Co.,Ltd.
 *
 *  openGauss is licensed under Mulan PSL v2.
 *  You can use this software according to the terms and conditions of the Mulan PSL v2.
 *  You may obtain a copy of Mulan PSL v2 at:
 *
 *        http://license.coscl.org.cn/MulanPSL2
 *  THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 *  EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 *  MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 *  See the Mulan PSL v2 for more details.
 *---------------------------------------------------------------------------------------
 *  plpy_util.h
 *      Definition about utility.
 *  IDENTIFICATION
 *      src/include/plpy_util.h
 *---------------------------------------------------------------------------------------
 */
#ifndef PLPY_UTIL_H
#define PLPY_UTIL_H

extern PyObject* PLyUnicode_Bytes(PyObject* unicode);
extern char* PLyUnicode_AsString(PyObject* unicode);

#if PY_MAJOR_VERSION >= 3
extern PyObject* PLyUnicode_FromString(const char* s);
#endif

#endif /* PLPY_UTIL_H */
