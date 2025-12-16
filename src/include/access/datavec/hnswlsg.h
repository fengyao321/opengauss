/*
 * Copyright (c) Huawei Technologies Co., Ltd. 2025-2025. All rights reserved.
 */

#ifndef HNSW_LSG_H
#define HNSW_LSG_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <cmath>
#include "access/datavec/utils.h"

#define HEAPTUPLE_HEAD_SIZE 40
#define MAX_LSG_SAMPLE_SIZE 5000
#define LSG_SAMPLE_INTERVAL 200

struct LsgCalculator {
    int sampleSize;
    int dim;
    float alpha;
    int degree;
    float* sampleVecs;
    LsgDistType distType;
};

float InnerProductDistance(float* a, float* b, int dim);
float NegativeInnerProductDistance(float* a, float* b, int dim);
float CosineDistance(float* a, float* b, int dim);
float SquaredL2Distance(float* a, float* b, int dim);
float FindKnnMu(float* a, LsgCalculator* params);
float CalcIsoVal(float* a, LsgCalculator* params);
void InitScalingParam(LsgCalculator* params, int sampleSize, int dim, float* inputSampleVecs, LsgDistType type,
                      int degree, float alpha);

#endif