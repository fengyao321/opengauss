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
 * -------------------------------------------------------------------------
 *
 * hnswlsg.cpp
 *
 * IDENTIFICATION
 *        src/gausskernel/storage/access/datavec/hnswlsg.cpp
 *
 * -------------------------------------------------------------------------
 */

#include <float.h>
#include <math.h>

#include "access/datavec/hnswlsg.h"


float InnerProductDistance(float* a, float* b, int dim)
{
    float sum = 0.0f;
    for (int i = 0; i < dim; ++i) {
        sum += a[i] * b[i];
    }
    return 1.0 - sum;
}

float NegativeInnerProductDistance(float* a, float* b, int dim)
{
    float sum = 0.0f;
    for (int i = 0; i < dim; ++i) {
        sum += a[i] * b[i];
    }
    return sum;
}

float CosineDistance(float* a, float* b, int dim)
{
    float dotProduct = 0.0f;
    float normA = 0.0f;
    float normB = 0.0f;
    float productAB = 0.0f;

    for (int i = 0; i < dim; ++i) {
        dotProduct += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
    }

    normA = sqrt(normA);
    normB = sqrt(normB);
    productAB = normA * normB;
    if (productAB == 0) {
        return 1.0f;
    } else {
        float cosSim = dotProduct / productAB;
        return 1.0f - cosSim;
    }
}

float SquaredL2Distance(float* a, float* b, int dim)
{
    float sum = 0.0f;
    for (int i = 0; i < dim; i++) {
        float diff = a[i] - b[i];
        sum += diff * diff;
    }
    return sqrt(sum);
}

float FindKnnMu(float* a, LsgCalculator* params)
{
    float distances[params->sampleSize];
    if (params->degree > params->sampleSize) {
        params->degree = params->sampleSize;
    }

    for (int i = 0; i < params->sampleSize; i++) {
        switch (params->distType) {
            case LSG_L2_DIST:
                distances[i] = SquaredL2Distance(a, params->sampleVecs + i * params->dim, params->dim);
                break;
            case LSG_IP_DIST:
                distances[i] = InnerProductDistance(a, params->sampleVecs + i * params->dim, params->dim);
                break;
            case LSG_COS_DIST:
                distances[i] = CosineDistance(a, params->sampleVecs + i * params->dim, params->dim);
                break;
            default:
                ereport(ERROR, (errmsg("LSG disttype invalid.")));
                break;
        }
    }

    for (int i = 0; i < params->degree; i++) {
        int minIndex = i;
        for (int j = i + 1; j < params->sampleSize; j++) {
            if (distances[j] < distances[minIndex]) {
                minIndex = j;
            }
        }
        float tempDist = distances[i];
        distances[i] = distances[minIndex];
        distances[minIndex] = tempDist;
    }

    float avgDistance = 0.0f;
    for (int i = 0; i < params->degree; i++) {
        avgDistance += sqrtf(distances[i]);
    }
    avgDistance = avgDistance / params->degree;
    return avgDistance;
}

float CalcIsoVal(float* a, LsgCalculator* params)
{
    float mu = FindKnnMu(a, params);
    if (mu == 0) {
        ereport(ERROR, (errmsg("HNSW LsgCalculator isolation is zero")));
    }
    return pow(1/mu, params->alpha);
}

void InitScalingParam(LsgCalculator* params, int sampleSize, int dim, float* inputSampleVecs, LsgDistType type,
                      int degree, float alpha)
{
    if (params == NULL || sampleSize <= 0 || dim <= 0 || degree < 0 || alpha < 0 || inputSampleVecs == nullptr) {
        ereport(ERROR, (errmsg("HNSW LocScalingParam init failed, parameter invalid.")));
        return;
    }
    params->sampleSize = sampleSize;
    params->dim = dim;
    params->distType = type;
    params->degree = degree;
    params->alpha = alpha;

    params->sampleVecs = (float*)palloc0(sizeof(float) * sampleSize * dim);
    for (int i = 0; i < sampleSize; i++) {
        errno_t rc =
            memcpy_s(params->sampleVecs + i * dim, dim * sizeof(float), inputSampleVecs + i * dim, dim * sizeof(float));
        securec_check(rc, "\0", "\0");
    }
}