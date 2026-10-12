#!/bin/bash
# ============================================================================
# openGauss Ustore Bridge Index Phase 4 Concurrency Test Runner
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GCC_LIBS="/home/fengyao/binarylibs/buildtools/gcc10.3/gcc/lib64:/home/fengyao/binarylibs/buildtools/gcc10.3/isl/lib:/home/fengyao/binarylibs/buildtools/gcc10.3/mpc/lib:/home/fengyao/binarylibs/buildtools/gcc10.3/mpfr/lib:/home/fengyao/binarylibs/buildtools/gcc10.3/gmp/lib"
export LD_LIBRARY_PATH="/usr/lib64:$GCC_LIBS:${BASE_DIR}/mppdb_temp_install/lib:$LD_LIBRARY_PATH"
export PATH="${BASE_DIR}/mppdb_temp_install/bin:$PATH"

echo ">>> Starting Bridge Index Concurrency Test Suite..."
python3 "${SCRIPT_DIR}/phase4_concurrency_test.py"
