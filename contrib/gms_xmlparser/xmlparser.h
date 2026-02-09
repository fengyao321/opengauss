/*---------------------------------------------------------------------------------------*
 * Copyright (c) 2024 Huawei Technologies Co.,Ltd.
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
 * gms_xmlparser.h
 *
 *  Definition about gms_xmlparser package.
 *
 * IDENTIFICATION
 *        contrib/gms_xmlparser/xmlparser.h
 *
 * ---------------------------------------------------------------------------------------
 */
#ifndef GMS_XMLPARSER_H
#define GMS_XMLPARSER_H

#include "postgres.h"
#include "fmgr.h"
#include "funcapi.h"

#include "utils/builtins.h"
#include "libpq/pqformat.h"
#include "libpq/libpq-fe.h"
#include "mb/pg_wchar.h"
#include "ctype.h"
#include "string.h"
#include "knl/knl_variable.h"
#include <libxml/tree.h>
#include <libxml/parser.h>

typedef struct {
    xmlParserCtxtPtr parser;
} XmlCtxt;

typedef struct {
    xmlDocPtr doc;
    bool isfreed ;
} _XmlDomDocument;

typedef _XmlDomDocument *XmlDomDocument;

extern "C" Datum gms_xmlparser_newparser(PG_FUNCTION_ARGS); 
extern "C" Datum gms_xmlparser_parser_in(PG_FUNCTION_ARGS);
extern "C" Datum gms_xmlparser_parser_out(PG_FUNCTION_ARGS);
extern "C" Datum gms_xmlparser_getdocument(PG_FUNCTION_ARGS);
extern "C" Datum gms_xmlparser_parsebuffer(PG_FUNCTION_ARGS);
extern "C" Datum gms_xmlparser_parseclob(PG_FUNCTION_ARGS);
extern "C" Datum gms_xmlparser_parse4func(PG_FUNCTION_ARGS);
extern "C" Datum gms_xmlparser_parse4proc(PG_FUNCTION_ARGS);
extern "C" Datum gms_xmlparser_freeparser(PG_FUNCTION_ARGS);
extern "C" Datum document_in(PG_FUNCTION_ARGS);
extern "C" Datum document_out(PG_FUNCTION_ARGS);
extern "C" Datum freedocument(PG_FUNCTION_ARGS);

#endif // GMS_XMLPARSER_H