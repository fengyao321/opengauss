#!/bin/bash
set -e

SCRIPT_DIR="/home/fengyao/openGauss-server"
PYTHON_SCRIPT="$SCRIPT_DIR/src/test/regress/run_adaptive_threshold_shrink_benchmark.py"
OUTPUT_REPORT="$SCRIPT_DIR/ubtree_shrink_doc/perf/adaptive_shrink_15min_report.md"
LOG_FILE="$SCRIPT_DIR/ubtree_shrink_doc/perf/adaptive_shrink_15min.log"

echo "=== Starting 15-Minute Adaptive Threshold Shrink Benchmark ==="
python3 -u "$PYTHON_SCRIPT" \
  --duration-mins 15 \
  --check-interval 15.0 \
  --threshold-pages 32 \
  --threshold-ratio 0.10 \
  --batch-size 150 \
  --ingest-delay 0.02 \
  --retain-window 30000 \
  --purge-interval 6.0 \
  --purge-batch 4000 \
  --output-report "$OUTPUT_REPORT" > "$LOG_FILE" 2>&1 &

PID=$!
echo "Benchmark successfully launched with PID: $PID"
echo "Log file: $LOG_FILE"
echo "Report file: $OUTPUT_REPORT"
