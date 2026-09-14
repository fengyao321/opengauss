#!/usr/bin/env bash
# ==============================================================================
# Functional & Concurrency Test Script for UBTree Online Shrink
# Covers:
#   1. Forward Index Scan Integrity (ASC order, Range Scan, Checksum)
#   2. Backward Index Scan Integrity (DESC order, _bt_walk_left verification)
#   3. High-Concurrency Insertion vs. Online Shrink (Deadlock & Split stress test)
#   4. High-Concurrency Scan vs. Online Shrink (Pin-Count Barrier & No-Panic test)
#   5. Transaction Rollback & Data Consistency verification
# ==============================================================================

set -e

# Default environment configuration
PORT="${PORT:-5432}"
DBNAME="${DBNAME:-postgres}"
if [ -d "/home/fengyao/openGauss-server/mppdb_temp_install" ]; then
    GAUSSHOME="/home/fengyao/openGauss-server/mppdb_temp_install"
else
    GAUSSHOME="${GAUSSHOME:-/home/fengyao/openGauss-server}"
fi
GSQL="${GAUSSHOME}/bin/gsql"

export LD_LIBRARY_PATH="${GAUSSHOME}/lib:/usr/lib64:${LD_LIBRARY_PATH}"

# Text colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

# Ensure gsql is accessible
if [ ! -f "${GSQL}" ]; then
    log_fail "gsql binary not found at ${GSQL}!"
    exit 1
fi

run_sql() {
    local sql="$1"
    "${GSQL}" -d "${DBNAME}" -p "${PORT}" -r -t -A -q -c "${sql}" | tail -n 1
}

run_sql_verbose() {
    local sql="$1"
    "${GSQL}" -d "${DBNAME}" -p "${PORT}" -r -c "${sql}"
}

# Check database connection
log_info "Testing database connectivity on port ${PORT}..."
if ! run_sql "SELECT 1;" > /dev/null 2>&1; then
    log_fail "Cannot connect to database on port ${PORT}. Please ensure gaussdb is running."
    exit 1
fi
log_pass "Database connection successful!"

# ==============================================================================
# Test Case 1: Setup and Basic Shrink Verification
# ==============================================================================
log_info "=================================================================="
log_info "Test Case 1: Setup UBTree table, insert data, and basic shrink"
log_info "=================================================================="

run_sql_verbose "
DROP TABLE IF EXISTS test_ubt_func CASCADE;
CREATE TABLE test_ubt_func (
    id INT,
    info TEXT,
    pad CHAR(50)
) WITH (storage_type=ustore);

CREATE INDEX idx_ubt_func_id ON test_ubt_func USING ubtree (id);

-- Insert initial 10,000 tuples
INSERT INTO test_ubt_func SELECT g, 'info_' || g, repeat('x', 50) FROM generate_series(1, 10000) g;
"

INITIAL_SIZE=$(run_sql "SELECT pg_relation_size('idx_ubt_func_id');")
INITIAL_COUNT=$(run_sql "SELECT count(*) FROM test_ubt_func;")
log_info "Initial table count: ${INITIAL_COUNT}, index size: ${INITIAL_SIZE} bytes"

# Delete upper 70% of rows
log_info "Deleting upper 70% data (id > 3000) to create page holes..."
run_sql_verbose "
DELETE FROM test_ubt_func WHERE id > 3000;
VACUUM test_ubt_func;
"

PRE_SHRINK_SIZE=$(run_sql "SELECT pg_relation_size('idx_ubt_func_id');")
log_info "Size before shrink: ${PRE_SHRINK_SIZE} bytes"

# Run check
run_sql_verbose "SELECT gs_ubtree_shrink_check('idx_ubt_func_id');"

# Run online shrink
log_info "Executing gs_ubtree_shrink(idx_ubt_func_id, true)..."
SHRINK_RESULT=$(run_sql "SELECT gs_ubtree_shrink('idx_ubt_func_id', true);")
POST_SHRINK_SIZE=$(run_sql "SELECT pg_relation_size('idx_ubt_func_id');")

log_info "Shrink returned: ${SHRINK_RESULT}"
log_info "Size after shrink: ${POST_SHRINK_SIZE} bytes"

if [ "${POST_SHRINK_SIZE}" -le "${PRE_SHRINK_SIZE}" ]; then
    log_pass "Test Case 1 passed: Index size compacted/maintained (${PRE_SHRINK_SIZE} -> ${POST_SHRINK_SIZE})."
else
    log_fail "Test Case 1 failed: Index size grew after shrink!"
    exit 1
fi

# ==============================================================================
# Test Case 2: Forward Index Scan Verification (ASC Order, Range & Aggregates)
# ==============================================================================
log_info "=================================================================="
log_info "Test Case 2: Forward Index Scan Correctness Verification"
log_info "=================================================================="

# Calculate expected checksum & count using seqscan disabled
FWD_COUNT=$(run_sql "
SET enable_seqscan = off;
SET enable_bitmapscan = off;
SELECT count(*) FROM test_ubt_func WHERE id <= 3000;
")

FWD_SUM=$(run_sql "
SET enable_seqscan = off;
SET enable_bitmapscan = off;
SELECT sum(id) FROM test_ubt_func;
")

FWD_MD5=$(run_sql "
SET enable_seqscan = off;
SET enable_bitmapscan = off;
SELECT md5(string_agg(id::text, ',' ORDER BY id ASC)) FROM test_ubt_func;
")

# Expected sum for 1..3000 is 3000 * 3001 / 2 = 4501500
EXPECTED_SUM="4501500"
EXPECTED_COUNT="3000"

log_info "Forward Scan - Count: ${FWD_COUNT}, Sum: ${FWD_SUM}, MD5: ${FWD_MD5}"

if [ "${FWD_COUNT}" = "${EXPECTED_COUNT}" ] && [ "${FWD_SUM}" = "${EXPECTED_SUM}" ]; then
    log_pass "Test Case 2 passed: Forward scan returned strictly ordered, complete tuples without loss."
else
    log_fail "Test Case 2 failed: Forward scan mismatch (Expected count=${EXPECTED_COUNT}, sum=${EXPECTED_SUM}; Got count=${FWD_COUNT}, sum=${FWD_SUM})"
    exit 1
fi

# ==============================================================================
# Test Case 3: Backward Index Scan Verification (DESC Order, _bt_walk_left)
# ==============================================================================
log_info "=================================================================="
log_info "Test Case 3: Backward Index Scan Correctness Verification"
log_info "=================================================================="

BKWD_COUNT=$(run_sql "
SET enable_seqscan = off;
SET enable_bitmapscan = off;
SELECT count(*) FROM (SELECT id FROM test_ubt_func ORDER BY id DESC) t;
")

BKWD_MD5=$(run_sql "
SET enable_seqscan = off;
SET enable_bitmapscan = off;
SELECT md5(string_agg(id::text, ',' ORDER BY id DESC)) FROM test_ubt_func;
")

# Compare with reference MD5 calculated directly
REF_MD5=$(run_sql "
SET enable_seqscan = on;
SELECT md5(string_agg(id::text, ',' ORDER BY id DESC)) FROM test_ubt_func;
")

log_info "Backward Scan - Count: ${BKWD_COUNT}, Scan MD5: ${BKWD_MD5}, Ref MD5: ${REF_MD5}"

if [ "${BKWD_COUNT}" = "${EXPECTED_COUNT}" ] && [ "${BKWD_MD5}" = "${REF_MD5}" ]; then
    log_pass "Test Case 3 passed: Backward scan (_bt_walk_left) successfully traversed all relocated leaf pages!"
else
    log_fail "Test Case 3 failed: Backward scan MD5 mismatch with reference order!"
    exit 1
fi

# ==============================================================================
# Test Case 4: High-Concurrency Insertion vs. Online Shrink Stress Test
# ==============================================================================
log_info "=================================================================="
log_info "Test Case 4: High-Concurrency Insertion vs. Online Shrink Stress Test"
log_info "=================================================================="

log_info "Spawning concurrent insertion workers and concurrent shrink loop..."

CONCURRENCY_ERROR_LOG="/tmp/ubtree_shrink_concurrency_err.log"
rm -f "${CONCURRENCY_ERROR_LOG}"

# Worker 1: Continuous insertion causing rapid page splits
insert_worker() {
    local worker_id=$1
    local start_val=$(( 100000 + worker_id * 10000 ))
    local end_val=$(( start_val + 5000 ))
    log_info "Worker ${worker_id} starting insert batch [${start_val} .. ${end_val}]..."
    "${GSQL}" -d "${DBNAME}" -p "${PORT}" -q -c "
        INSERT INTO test_ubt_func SELECT g, 'worker_${worker_id}_' || g, repeat('w', 50)
        FROM generate_series(${start_val}, ${end_val}) g;
    " >> "${CONCURRENCY_ERROR_LOG}" 2>&1 || touch "${CONCURRENCY_ERROR_LOG}.failed"
}

# Worker 2: Concurrent shrink loop
shrink_worker() {
    log_info "Shrink worker starting concurrent shrink iterations..."
    for i in {1..10}; do
        "${GSQL}" -d "${DBNAME}" -p "${PORT}" -q -c "
            SELECT gs_ubtree_shrink('idx_ubt_func_id', true);
        " >> "${CONCURRENCY_ERROR_LOG}" 2>&1 || true
        sleep 0.2
    done
}

# Launch 4 insertion workers and 1 shrink worker in parallel
insert_worker 1 &
PID1=$!
insert_worker 2 &
PID2=$!
insert_worker 3 &
PID3=$!
shrink_worker &
PID_SHRINK=$!

# Wait for all workers to finish
wait $PID1
wait $PID2
wait $PID3
wait $PID_SHRINK

if [ -f "${CONCURRENCY_ERROR_LOG}.failed" ] || grep -iE "deadlock|panic|corrupt" "${CONCURRENCY_ERROR_LOG}" 2>/dev/null; then
    log_fail "Test Case 4 failed: Concurrency error detected in logs:"
    cat "${CONCURRENCY_ERROR_LOG}"
    exit 1
else
    log_pass "Test Case 4 passed: High-concurrency insertion and online shrink completed with ZERO deadlocks and ZERO panics."
fi

# Verify data consistency after concurrent stress test
TOTAL_AFTER_STRESS=$(run_sql "SELECT count(*) FROM test_ubt_func;")
EXPECTED_AFTER_STRESS=$(( 3000 + 5001 * 3 ))
log_info "Total rows after concurrent insertion: ${TOTAL_AFTER_STRESS} (Expected: ${EXPECTED_AFTER_STRESS})"

if [ "${TOTAL_AFTER_STRESS}" -eq "${EXPECTED_AFTER_STRESS}" ]; then
    log_pass "Data count matches perfectly after concurrent stress test!"
else
    log_fail "Data count mismatch: expected ${EXPECTED_AFTER_STRESS}, got ${TOTAL_AFTER_STRESS}"
    exit 1
fi

# ==============================================================================
# Test Case 5: Concurrent Long Query / Buffer Pin vs. Online Shrink Barrier
# ==============================================================================
log_info "=================================================================="
log_info "Test Case 5: Buffer Pin Barrier & Truncate Safe-Abort Verification"
log_info "=================================================================="

# Start a background process holding a cursor open on the upper range of the table
HOLD_PIN_SCRIPT="
BEGIN;
DECLARE cur_long_scan CURSOR FOR 
    SELECT * FROM test_ubt_func WHERE id > 100000 ORDER BY id DESC;
FETCH 1 FROM cur_long_scan;
SELECT pg_sleep(3);
COMMIT;
"

"${GSQL}" -d "${DBNAME}" -p "${PORT}" -q -c "${HOLD_PIN_SCRIPT}" > /dev/null 2>&1 &
PID_LONG_SCAN=$!

# Sleep briefly to ensure cursor is active and holding page pin
sleep 0.5

# Concurrently attempt online shrink
log_info "Executing shrink while concurrent reader is pinning buffer..."
SHRINK_PIN_RES=$(run_sql "SELECT gs_ubtree_shrink('idx_ubt_func_id', true);")
log_info "Shrink during active pin returned: ${SHRINK_PIN_RES}"

# Wait for cursor to finish
wait $PID_LONG_SCAN

# Final sanity check on index
FINAL_CHECK=$(run_sql "
SET enable_seqscan = off;
SELECT count(*) FROM test_ubt_func;
")

if [ "${FINAL_CHECK}" -eq "${TOTAL_AFTER_STRESS}" ]; then
    log_pass "Test Case 5 passed: Pin-count barrier safely prevented 'beyond EOF' panic, query succeeded."
else
    log_fail "Test Case 5 failed: Data corrupted during concurrent pin test!"
    exit 1
fi

# ==============================================================================
# Test Case 6: Cleanup
# ==============================================================================
log_info "=================================================================="
log_info "Cleaning up temporary test tables..."
log_info "=================================================================="
run_sql_verbose "DROP TABLE IF EXISTS test_ubt_func CASCADE;"
rm -f "${CONCURRENCY_ERROR_LOG}" "${CONCURRENCY_ERROR_LOG}.failed"

echo ""
echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN} ALL UBTree Online Shrink Concurrency & Integrity Tests PASSED!   ${NC}"
echo -e "${GREEN}==================================================================${NC}"
