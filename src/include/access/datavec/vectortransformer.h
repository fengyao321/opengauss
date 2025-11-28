#ifndef VECTORTRANSFORMER_H
#define VECTORTRANSFORMER_H

#include "postgres.h"

#include "nodes/execnodes.h"
#include "access/datavec/vector.h"

#include <random>

#define MAX_RETRIES 5
#define FHT_ROUND 4


enum VectorTransformType {
    RANDOM_ORTHOGONAL, /* Random Orthogonal Matrix */
    FAST_HTRANSFORM /* Fast Walsh-Hadamard Transform Matrix */
};

typedef struct VectorTransform VectorTransform;

struct VectorTransform {
    VectorTransformType type;
    int dim;
    
    /* ROM */
    float* matrix;

    /* FHT */
    int power2Dim;
    float fac;
    uint8 *matfht;
};

struct RandomGenerator {
    std::mt19937 mt;

    /// random positive integer
    int rand_int()
    {
        return mt() & 0x7fffffff;
    }

    double rand_double()
    {
        return mt() / double(mt.max());
    }

    uint8_t rand_uint8()
    {
        return static_cast<uint8_t>(rand_int() % 256);
    }

    explicit RandomGenerator(int64_t seed = 1234) : mt((unsigned int)seed) {}
};

void RomTrain(VectorTransform* vtrans);
void RomTransform(VectorTransform* vtrans, const float* vec, float *transvec);
void *RomGetMatrix(VectorTransform* vtrans);
void FhtInit(VectorTransform* vtrans);
void FhtTrain(VectorTransform* vtrans);
void FhtTransform(VectorTransform* vtrans, const float* vec, float *transvec);
void *FhtGetMatrix(VectorTransform* vtrans);


#endif