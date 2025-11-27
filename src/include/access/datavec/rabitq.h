#ifndef RABITQ_H
#define RABITQ_H

#include "postgres.h"

#include "access/genam.h"
#include "nodes/execnodes.h"
#include "access/datavec/vector.h"
#include "access/datavec/vectortransformer.h"
#include "access/datavec/utils.h"

typedef struct RabitQConfig {
    bool FHT;
    VectorTransform* vtrans;
    int rbqQueryBits;
} RabitQConfig;

typedef struct FactorData {
    float orMinusCL2Sqr;
    float xbSum;
    float dpMultiplier;
    uint32 unused;
} FactorData;

typedef struct RabitqVector {
    FactorData fac;
    uint8 data[FLEXIBLE_ARRAY_MEMBER];
} RabitqVector;

typedef struct QueryFactorData {
    float cof1;
    float cof2;
    float cof34;
    
    float qrMinusCL2Sqr;
    float qrNormL2Sqr;
} QueryFactorData;

typedef struct QueryRabitqVector {
    QueryFactorData fac;
    uint8 data[FLEXIBLE_ARRAY_MEMBER];
} QueryRabitqVector;

typedef struct RabitqInsertOnDiskParams {
    Relation heap;
    Datum originInsertVec;
    VectorTransform* vtrans;
} RabitqInsertOnDiskParams;

typedef struct RabitqQueryParams {
    int dim;
    int funcType;
    float *centroid;
    RabitQConfig *rbqConfig;
    QueryRabitqVector* qrbqVec;
} RabitqQueryParams;

#define rbqCodeSize(d) MAXALIGN(sizeof(FactorData) + (d + 7) / 8)
#define rbqQuerySize(d, qb) MAXALIGN(sizeof(QueryFactorData) + ((d + 7) / 8) * qb)

void ComputeVectorRBQCode(int dim, float *vec, RabitqVector *rbqVec, float *centroid, int funcType);
void SetRBQQuery(int dim, int qb, float *vec, QueryRabitqVector *qrbqVec, float *centroid, int funcType);
float ComputeRbqDistance(int dim, int qb, RabitqVector *eVec, QueryRabitqVector *qVec, int funcType);

#endif