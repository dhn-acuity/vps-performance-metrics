#!/usr/bin/env bash
set -euo pipefail

# Script to capture performance test results with metadata
# Usage: ./capture_results.sh <vps_name> <test_description>

VPS_NAME="${1:-vps-unknown}"
TEST_DESC="${2:-performance-test}"
TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
RESULTS_DIR="./results"
OUTPUT_FILE="${RESULTS_DIR}/${VPS_NAME}_${TIMESTAMP}.json"

mkdir -p "$RESULTS_DIR"

echo "======================================"
echo " Capturing Performance Test Results"
echo " VPS: $VPS_NAME"
echo " Description: $TEST_DESC"
echo " Output: $OUTPUT_FILE"
echo "======================================"

# Capture final metrics snapshot
METRICS=$(curl -s http://127.0.0.1:3000/metrics)

# Get system info
CPU_CORES=$(echo "$METRICS" | jq -r '.cpu.cores')
TOTAL_MEM=$(echo "$METRICS" | jq -r '.memory.totalMB')

# Build complete result JSON
cat > "$OUTPUT_FILE" << EOF
{
  "metadata": {
    "vps_name": "$VPS_NAME",
    "test_description": "$TEST_DESC",
    "timestamp": "$TIMESTAMP",
    "date_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  },
  "system": {
    "cpu_cores": $CPU_CORES,
    "total_memory_mb": $TOTAL_MEM
  },
  "final_metrics": $METRICS,
  "test_parameters": {
    "note": "Add your test parameters here manually or via script arguments"
  }
}
EOF

echo ""
echo "✅ Results captured successfully!"
echo ""
echo "View results:"
echo "  cat $OUTPUT_FILE | jq"
echo ""
echo "Compare with another VPS:"
echo "  ./compare_results.sh $OUTPUT_FILE results/other_vps_*.json"
