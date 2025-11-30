#include <float.h>
#include "access/datavec/scalarquantizer.h"


ScalarQuantizer *InitScalarQuantizer(int dim)
{
    Size size = dim * sizeof(float);
    ScalarQuantizer *sq = (ScalarQuantizer *)palloc(sizeof(ScalarQuantizer));
    sq->dim = dim;
    sq->decodeVec = NULL;
    sq->trained = (float *)palloc(size * 2);
    float a = FLT_MAX;
    float b = -FLT_MAX;
    int i;

    for (i = 0; i < dim; i++) {
        sq->trained[i] = a;
    }
    for (i = dim; i < 2 * dim; i++) {
        sq->trained[i] = b;
    }
    return sq;
}

void FreeScalarQuantizer(ScalarQuantizer *sq)
{
    pfree(sq->trained);
    if (sq->decodeVec != NULL) {
        pfree(sq->decodeVec);
    }
    pfree(sq);
}