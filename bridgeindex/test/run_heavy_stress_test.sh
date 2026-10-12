#!/bin/bash
# ============================================================================
# openGauss Ustore Bridge Index Phase 5 Heavy Stress & Plan Verification Runner
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

GCC_LIBS="/home/fengyao/binarylibs/buildtools/gcc10.3/gcc/lib64:/home/fengyao/binarylibs/buildtools/gcc10.3/isl/lib:/home/fengyao/binarylibs/buildtools/gcc10.3/mpc/lib:/home/fengyao/binarylibs/buildtools/gcc10.3/mpfr/lib:/home/fengyao/binarylibs/buildtools/gcc10.3/gmp/lib"
export LD_LIBRARY_PATH="/usr/lib64:$GCC_LIBS:${BASE_DIR}/mppdb_temp_install/lib:$LD_LIBRARY_PATH"
export PATH="${BASE_DIR}/mppdb_temp_install/bin:$PATH"

echo ">>> Starting Phase 5 Heavy Stress & Execution Plan Verification Suite..."
python3 "${SCRIPT_DIR}/phase5_heavy_stress_and_plan_test.py"
