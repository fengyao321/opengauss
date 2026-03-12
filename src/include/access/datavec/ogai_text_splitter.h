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
 * ogai_text_splitter.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_text_splitter.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OGAI_TEXT_SPLITTER_H
#define OGAI_TEXT_SPLITTER_H

typedef enum TextSplitParserKind {
    TEXT_SPLIT_PARSER_TEXT = 0,
    TEXT_SPLIT_PARSER_MARKDOWN,
    TEXT_SPLIT_PARSER_CODE
} TextSplitParserKind;

typedef struct TextSplitConfig {
    int maxChunkSize;
    int maxChunkOverlap;
    TextSplitParserKind parserKind;
} TextSplitConfig;

typedef struct TextSplitChunk {
    char* chunk;        /* palloc'd via pnstrdup */
    int chunkOffset;
    int chunkLength;
} TextSplitChunk;

typedef struct TextSplitResult {
    TextSplitChunk* chunks;   /* palloc'd array */
    int chunkCount;
} TextSplitResult;

typedef struct SemanticRun {
    int level;
    int startByte;
    int endByte;
} SemanticRun;

typedef struct SemanticRunArray {
    SemanticRun* items;
    int count;
    int capacity;
} SemanticRunArray;

void InitSemanticRunArray(SemanticRunArray* runs, int capacity);
void AddSemanticRun(SemanticRunArray* runs, int level, int startByte, int endByte);
void FreeSemanticRunArray(SemanticRunArray* runs);
TextSplitConfig BuildDefaultTextSplitConfig(int maxChunkSize, int maxChunkOverlap);
void SplitTextByConfig(const char* document, const TextSplitConfig* config, TextSplitResult* result);

#endif   /* OGAI_TEXT_SPLITTER_H */
