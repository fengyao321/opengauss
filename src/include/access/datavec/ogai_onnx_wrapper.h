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
 * ogai_onnx_wrapper.h
 *
 * IDENTIFICATION
 *        src/include/access/datavec/ogai_onnx_wrapper.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef OGAI_ONNX_WRAPPER_H
#define OGAI_ONNX_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void* ONNXModelHandle;

typedef void* ONNXEnvHandle;

/**
 * @brief create onnx runtime env handle for model
 * @return onnx runtime env handle, return NULL if error
 */
ONNXEnvHandle ONNXEnvCreate();

/**
 * @brief release onnx runtime env instance
 * @param onnxEnvHandle: onnx env instance
 */
void ONNXEnvRelease(ONNXEnvHandle onnxEnvHandle);

/**
 * @brief load onnx model
 * @param onnxEnvHandle: onnx env instance
 * @param modelPath: path to model
 * @param tokenizerPath: path to tokenizer.json (can be NULL)
 * @param dim: embedding dimension
 * @return model handle, NULL if error
 */
ONNXModelHandle ONNXLoadModel(ONNXEnvHandle onnxEnvHandle, const char* modelPath, const char* tokenizerPath, int* dim);

/**
 * @brief upload onnx model
 * @param handle: onnx model instance
 */
void ONNXUnloadModel(ONNXModelHandle handle);

/**
 * @brief Perform embedding inference on a single text
 * @param handle Instance handle
 * @param text Input text
 * @param embedding Output embedding vector (caller is responsible for memory allocation)
 * @param dim Dimension of the embedding
 * @return 0 indicates failure, 1 indicates success
 */
int ONNXEmbeddingInfer(ONNXModelHandle handle, const char* text, float* embedding, int dim);


/**
 * @brief Perform embedding inference on multiple texts (batch processing)
 * @param handle Instance handle
 * @param texts Array of input texts
 * @param numTexts Number of texts
 * @param embeddings Array of output embedding vectors (caller is responsible for memory allocation)
 * @param dim Dimension of each embedding
 * @return 0 indicates success, 1 indicates failure
 */
int ONNXEmbeddingInferBatch(ONNXModelHandle handle, char** texts, int numTexts, float** embeddings, int dim);

/**
 * @brief Get the embedding dimension of the model
 * @param handle Instance handle
 * @return Embedding dimension, returns -1 if model is not loaded
*/
int ONNXGetEmbeddingDim(ONNXModelHandle handle);

#ifdef __cplusplus
}
#endif

#endif // OGAI_ONNX_WRAPPER_H