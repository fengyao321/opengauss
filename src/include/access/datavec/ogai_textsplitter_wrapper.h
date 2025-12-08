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
 * ogai_textsplitter_wrapper.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_textsplitter_wrapper.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OGAI_TEXTSPLITTER_H
#define OGAI_TEXTSPLITTER_H

#include "postgres.h"
#include "utils/memutils.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Chunk {
    char* chunk;
} Chunk;

typedef struct ChunkResult {
    Chunk* chunks;
    int chunkNum;
} ChunkResult;

typedef void* TextSplitterHandle;

TextSplitterHandle CreateTextSplitter(int max_chunk_size, int max_chunk_overlap);
void FreeTextSplitter(TextSplitterHandle handle);
char** SplitText(TextSplitterHandle handle, const char* document, int* chunkNum);
void FreeSplitResult(char** chunks);

#ifdef __cplusplus
}
#endif

class TextSplitterWrapper {
public:
    TextSplitterWrapper(int maxChunkSize, int maxChunkOverlap)
    {
        handle = CreateTextSplitter(maxChunkSize, maxChunkOverlap);
    }

    ~TextSplitterWrapper()
    {
        if (handle == nullptr) return;
        FreeTextSplitter(handle);
    }

    ChunkResult* split(const char* document)
    {
        int chunkNum = 0;
        char** chunks = SplitText(handle, document, &chunkNum);
        if (chunkNum == 0) {
            return nullptr;
        }
        Chunk* returnChunks = (Chunk*)palloc0(sizeof(Chunk) * chunkNum);
        for (int i = 0; i < chunkNum; i++) {
            char* chunk = pg_strdup(chunks[i]);
            returnChunks[i] = {chunk};
        }
        FreeSplitResult(chunks);
        ChunkResult* chunksResult = (ChunkResult*)palloc0(sizeof(ChunkResult));
        chunksResult->chunks = returnChunks;
        chunksResult->chunkNum = chunkNum;
        return chunksResult;
    }

private:
    TextSplitterHandle handle;
};

#endif // OGAI_TEXTSPLITTER_H
