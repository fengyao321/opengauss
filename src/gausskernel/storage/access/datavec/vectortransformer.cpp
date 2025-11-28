#include "access/datavec/vectortransformer.h"

#include <lapacke.h>
#include <cblas.h>

void FloatRandom(float* x, size_t n, int64_t seed)
{
    return;
}

/*
 * QR decomposition
 */
bool MatrixQR(int dim, float* x)
{
    return true;
}

void RomTrain(VectorTransform* vtrans)
{
    return;
}

void RomTransform(VectorTransform* vtrans, const float* vec, float *transvec)
{
    return;
    
}

void *RomGetMatrix(VectorTransform* vtrans)
{
    return (void *)vtrans->matrix;
}

inline int Log2Floor(int dim)
{
    return 0;
}

void Uint8Random(uint8 *x, size_t n, int64_t seed)
{
    return;
}

void FhtInit(VectorTransform* vtrans)
{
    return;
}

void FhtTrain(VectorTransform* vtrans)
{
    return;
}

void FhtTransform(VectorTransform* vtrans, const float* vec, float *transvec)
{
    return;
}

void *FhtGetMatrix(VectorTransform* vtrans)
{
    return (void *)vtrans->matfht;
}