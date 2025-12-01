#ifndef SCALARQUANTIZER_H
#define SCALARQUANTIZER_H

#include "postgres.h"
#include "access/genam.h"
#include "nodes/execnodes.h"
#include "access/datavec/vector.h"

#define SQ_RANGE 255.0f

typedef struct ScalarQuantizer {
    int dim;
    float *trained; /* min+diff, the num of trained is 2*dim */
    Vector *decodeVec;
} ScalarQuantizer;

ScalarQuantizer *InitScalarQuantizer(int dim);
void FreeScalarQuantizer(ScalarQuantizer *sq);

#endif