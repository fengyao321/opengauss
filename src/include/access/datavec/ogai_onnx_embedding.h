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
 * ogai_onnx_embedding.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_onnx_embedding.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OGAI_ONNX_EMBEDDING_H
#define OGAI_ONNX_EMBEDDING_H

EmbeddingClient* CreateONNXEmbeddingClient(ModelConfig* config);

class ONNXEmbeddingClient : public EmbeddingClient {
public:
    ONNXEmbeddingClient(ModelConfig* modelConfig)
    {
        config = modelConfig;
    }
    char* BuildEmbeddingReqBody(OGAIString* texts, size_t textNum) override;
    void ParseEmbeddingRespBody(char* respBody, Vector** results, size_t start, size_t textNum) override;
    Vector** BatchEmbed(OGAIString* texts, size_t textNum, int* dim) override;
};

#endif // OGAI_ONNX_EMBEDDING_H
