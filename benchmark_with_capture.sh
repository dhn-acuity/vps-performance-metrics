#!/usr/bin/env bash
set -euo pipefail

# Enhanced benchmark script that captures results automatically
# Usage: ./benchmark_with_capture.sh <VPS_IP> <VPS_NAME>

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <VPS_IP> <VPS_NAME>"
  echo "Example: $0 192.168.1.100 aws-t3-medium"
  exit 1
fi

VPS_IP="$1"
VPS_NAME="$2"
VPS_URL="http://${VPS_IP}:3000"
ENDPOINT="/metrics"

THREADS=4
DURATION="60s"
CONCURRENCY=(50 100 200 400 600 800 1000)
POLL_EVERY=2

TIMESTAMP=$(date -u +%Y%m%d_%H%M%S)
RESULTS_DIR="./results"
OUTPUT_FILE="${RESULTS_DIR}/${VPS_NAME}_${TIMESTAMP}.json"
LOG_FILE="${RESULTS_DIR}/${VPS_NAME}_${TIMESTAMP}.log"

mkdir -p "$RESULTS_DIR"

echo "======================================"
echo " Auto-stop benchmark with capture"
echo " VPS: $VPS_NAME"
echo " Target: $VPS_URL$ENDPOINT"
echo " Results: $OUTPUT_FILE"
echo "======================================"

# Capture initial state
echo "Capturing initial metrics..."
INITIAL_METRICS=$(curl -s "$VPS_URL/metrics")
INITIAL_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Store initial data
cat > "$OUTPUT_FILE" << EOF
{
  "metadata": {
    "vps_name": "$VPS_NAME",
    "vps_ip": "$VPS_IP",
    "test_start": "$INITIAL_TIMESTAMP",
    "test_duration_per_step": "$DURATION",
    "threads": $THREADS
  },
  "system": {
    "cpu_cores": $(echo "$INITIAL_METRICS" | jq '.cpu.cores'),
    "total_memory_mb": $(echo "$INITIAL_METRICS" | jq '.memory.totalMB')
  },
  "initial_metrics": $INITIAL_METRICS,
  "test_results": [
EOF

FIRST_STEP=true
MAX_RPS=0
SAFE_CONCURRENCY=0

for c in "${CONCURRENCY[@]}"; do
  echo "" | tee -a "$LOG_FILE"
  echo ">>> Concurrency: $c" | tee -a "$LOG_FILE"
  echo "--------------------------------------" | tee -a "$LOG_FILE"

  # Run wrk in background
  WRK_OUTPUT=$(mktemp)
  wrk -t"$THREADS" -c"$c" -d"$DURATION" --latency "$VPS_URL$ENDPOINT" > "$WRK_OUTPUT" 2>&1 &
  WRK_PID=$!

  STOPPED_EARLY=false

  # Monitor loop
  while kill -0 "$WRK_PID" 2>/dev/null; do
    sleep "$POLL_EVERY"

    JSON=$(curl -s "$VPS_URL/metrics" || true)
    if [[ -z "$JSON" ]]; then
      continue
    fi

    ELU=$(echo "$JSON" | jq -r '.eventLoop.elu.utilization')
    OVERLOADED=$(echo "$JSON" | jq -r '.eventLoop.overloaded')
    THRESH=$(echo "$JSON" | jq -r '.eventLoop.threshold')

    echo "ELU=$ELU threshold=$THRESH overloaded=$OVERLOADED" | tee -a "$LOG_FILE"

    if [[ "$OVERLOADED" == "true" ]]; then
      echo "🔥 ELU >= $THRESH — stopping test" | tee -a "$LOG_FILE"
      kill -9 "$WRK_PID" || true
      wait "$WRK_PID" 2>/dev/null || true
      STOPPED_EARLY=true
      break
    fi
  done

  # Capture final metrics for this step
  FINAL_METRICS=$(curl -s "$VPS_URL/metrics")
  
  # Parse wrk output - clean and sanitize values
  # Extract only the numeric value, avoid multi-line captures
  RPS=$(grep "Requests/sec:" "$WRK_OUTPUT" | head -1 | awk '{print $2}' | sed 's/[^0-9.]//g' || echo "0")
  LAT_AVG=$(grep -A 0 "^  Latency" "$WRK_OUTPUT" | head -1 | awk '{print $2}' || echo "0ms")
  LAT_P95=$(grep "99.000%" "$WRK_OUTPUT" | awk '{print $2}' || echo "0ms")
  
  # If P95 not found, try alternative format
  if [ "$LAT_P95" = "0ms" ]; then
    LAT_P95=$(grep "95%" "$WRK_OUTPUT" | tail -1 | awk '{print $2}' || echo "0ms")
  fi
  
  # Remove any trailing newlines and spaces
  LAT_AVG=$(echo "$LAT_AVG" | tr -d '\r\n' | xargs)
  LAT_P95=$(echo "$LAT_P95" | tr -d '\r\n' | xargs)
  
  echo "Results: RPS=$RPS, Latency Avg=$LAT_AVG, P95=$LAT_P95" | tee -a "$LOG_FILE"

  # Track max safe RPS
  if (( $(echo "$RPS > $MAX_RPS" | bc -l) )); then
    MAX_RPS="$RPS"
    SAFE_CONCURRENCY=$c
  fi

  # Append to results JSON
  if [ "$FIRST_STEP" = false ]; then
    echo "," >> "$OUTPUT_FILE"
  fi
  FIRST_STEP=false

  # Properly escape JSON string values and ensure metrics is valid JSON
  LAT_AVG_ESCAPED=$(echo "$LAT_AVG" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
  LAT_P95_ESCAPED=$(echo "$LAT_P95" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
  
  # Validate and minify FINAL_METRICS JSON
  FINAL_METRICS_CLEAN=$(echo "$FINAL_METRICS" | jq -c . 2>/dev/null || echo '{}')

  cat >> "$OUTPUT_FILE" << EOF
    {
      "concurrency": $c,
      "requests_per_sec": $RPS,
      "wrk_latency_avg": "$LAT_AVG_ESCAPED",
      "wrk_latency_p95": "$LAT_P95_ESCAPED",
      "stopped_early": $STOPPED_EARLY,
      "metrics": $FINAL_METRICS_CLEAN
    }
EOF

  rm -f "$WRK_OUTPUT"

  if [ "$STOPPED_EARLY" = true ]; then
    echo "SAFE MAX CAPACITY REACHED" | tee -a "$LOG_FILE"
    break
  fi

  echo "Cooldown 15s..." | tee -a "$LOG_FILE"
  sleep 15
done

# Finalize JSON
TEST_END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RPM=$(echo "$MAX_RPS * 60" | bc)

cat >> "$OUTPUT_FILE" << EOF

  ],
  "summary": {
    "test_end": "$TEST_END",
    "max_requests_per_sec": $MAX_RPS,
    "max_requests_per_minute": $RPM,
    "safe_concurrency_level": $SAFE_CONCURRENCY,
    "test_completed": true
  }
}
EOF

echo "" | tee -a "$LOG_FILE"
echo "======================================"
echo " Test Complete"
echo "======================================"
echo "VPS: $VPS_NAME"
echo "Max RPS: $MAX_RPS"
echo "Max RPM: $RPM"
echo "Safe Concurrency: $SAFE_CONCURRENCY"
echo ""
echo "Results saved to: $OUTPUT_FILE"
echo "Logs saved to: $LOG_FILE"
echo ""
echo "View results:"
echo "  cat $OUTPUT_FILE | jq"
echo ""
echo "Compare with another VPS:"
echo "  ./compare_results.sh $OUTPUT_FILE results/other_vps_*.json"
