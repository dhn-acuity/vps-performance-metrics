#!/usr/bin/env bash
set -euo pipefail

# Script to compare performance results between two VPS systems
# Usage: ./compare_results.sh <result_file_1.json> <result_file_2.json>

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <result_file_1.json> <result_file_2.json>"
  exit 1
fi

FILE1="$1"
FILE2="$2"

if [ ! -f "$FILE1" ]; then
  echo "Error: File not found: $FILE1"
  exit 1
fi

if [ ! -f "$FILE2" ]; then
  echo "Error: File not found: $FILE2"
  exit 1
fi

echo "======================================"
echo " VPS Performance Comparison"
echo "======================================"
echo ""

# Extract metadata
VPS1_NAME=$(jq -r '.metadata.vps_name' "$FILE1")
VPS2_NAME=$(jq -r '.metadata.vps_name' "$FILE2")
VPS1_DATE=$(jq -r '.metadata.date_utc' "$FILE1")
VPS2_DATE=$(jq -r '.metadata.date_utc' "$FILE2")

echo "VPS 1: $VPS1_NAME (tested: $VPS1_DATE)"
echo "VPS 2: $VPS2_NAME (tested: $VPS2_DATE)"
echo ""

# System specs comparison
echo "======================================"
echo " System Specifications"
echo "======================================"
printf "%-20s | %-15s | %-15s\n" "Metric" "VPS 1" "VPS 2"
echo "--------------------------------------------------------------"

CPU1=$(jq -r '.system.cpu_cores' "$FILE1")
CPU2=$(jq -r '.system.cpu_cores' "$FILE2")
printf "%-20s | %-15s | %-15s\n" "CPU Cores" "$CPU1" "$CPU2"

MEM1=$(jq -r '.system.total_memory_mb' "$FILE1")
MEM2=$(jq -r '.system.total_memory_mb' "$FILE2")
printf "%-20s | %-15s | %-15s\n" "Total Memory (MB)" "$MEM1" "$MEM2"

echo ""
echo "======================================"
echo " Performance Metrics"
echo "======================================"
printf "%-25s | %-15s | %-15s | %-10s\n" "Metric" "VPS 1" "VPS 2" "Winner"
echo "--------------------------------------------------------------------------------"

# CPU Usage (lower is better for idle state)
CPU_USAGE1=$(jq -r '.final_metrics.cpu.usagePercent' "$FILE1")
CPU_USAGE2=$(jq -r '.final_metrics.cpu.usagePercent' "$FILE2")
WINNER=$(awk "BEGIN {print ($CPU_USAGE1 < $CPU_USAGE2) ? \"VPS 1\" : \"VPS 2\"}")
printf "%-25s | %-15s | %-15s | %-10s\n" "CPU Usage %" "$CPU_USAGE1" "$CPU_USAGE2" "$WINNER"

# Memory Usage (lower is better)
MEM_USAGE1=$(jq -r '.final_metrics.memory.usagePercent' "$FILE1")
MEM_USAGE2=$(jq -r '.final_metrics.memory.usagePercent' "$FILE2")
WINNER=$(awk "BEGIN {print ($MEM_USAGE1 < $MEM_USAGE2) ? \"VPS 1\" : \"VPS 2\"}")
printf "%-25s | %-15s | %-15s | %-10s\n" "Memory Usage %" "$MEM_USAGE1" "$MEM_USAGE2" "$WINNER"

# Event Loop Utilization (lower is better)
ELU1=$(jq -r '.final_metrics.eventLoop.elu.utilization' "$FILE1")
ELU2=$(jq -r '.final_metrics.eventLoop.elu.utilization' "$FILE2")
WINNER=$(awk "BEGIN {print ($ELU1 < $ELU2) ? \"VPS 1\" : \"VPS 2\"}")
printf "%-25s | %-15s | %-15s | %-10s\n" "ELU" "$ELU1" "$ELU2" "$WINNER"

# Event Loop Lag P95 (lower is better)
LAG_P95_1=$(jq -r '.final_metrics.eventLoop.lag.p95Ms' "$FILE1")
LAG_P95_2=$(jq -r '.final_metrics.eventLoop.lag.p95Ms' "$FILE2")
WINNER=$(awk "BEGIN {print ($LAG_P95_1 < $LAG_P95_2) ? \"VPS 1\" : \"VPS 2\"}")
printf "%-25s | %-15s | %-15s | %-10s\n" "Event Loop Lag P95 (ms)" "$LAG_P95_1" "$LAG_P95_2" "$WINNER"

# Latency P50 (lower is better)
LAT_P50_1=$(jq -r '.final_metrics.latency.p50Ms' "$FILE1")
LAT_P50_2=$(jq -r '.final_metrics.latency.p50Ms' "$FILE2")
WINNER=$(awk "BEGIN {print ($LAT_P50_1 < $LAT_P50_2) ? \"VPS 1\" : \"VPS 2\"}")
printf "%-25s | %-15s | %-15s | %-10s\n" "Latency P50 (ms)" "$LAT_P50_1" "$LAT_P50_2" "$WINNER"

# Latency P95 (lower is better)
LAT_P95_1=$(jq -r '.final_metrics.latency.p95Ms' "$FILE1")
LAT_P95_2=$(jq -r '.final_metrics.latency.p95Ms' "$FILE2")
WINNER=$(awk "BEGIN {print ($LAT_P95_1 < $LAT_P95_2) ? \"VPS 1\" : \"VPS 2\"}")
printf "%-25s | %-15s | %-15s | %-10s\n" "Latency P95 (ms)" "$LAT_P95_1" "$LAT_P95_2" "$WINNER"

# Latency P99 (lower is better)
LAT_P99_1=$(jq -r '.final_metrics.latency.p99Ms' "$FILE1")
LAT_P99_2=$(jq -r '.final_metrics.latency.p99Ms' "$FILE2")
WINNER=$(awk "BEGIN {print ($LAT_P99_1 < $LAT_P99_2) ? \"VPS 1\" : \"VPS 2\"}")
printf "%-25s | %-15s | %-15s | %-10s\n" "Latency P99 (ms)" "$LAT_P99_1" "$LAT_P99_2" "$WINNER"

# Total Requests in Window (higher is better)
REQ1=$(jq -r '.final_metrics.latency.requests' "$FILE1")
REQ2=$(jq -r '.final_metrics.latency.requests' "$FILE2")
WINNER=$(awk "BEGIN {print ($REQ1 > $REQ2) ? \"VPS 1\" : \"VPS 2\"}")
printf "%-25s | %-15s | %-15s | %-10s\n" "Requests (10s window)" "$REQ1" "$REQ2" "$WINNER"

# Network RX (if available)
RX1=$(jq -r '.final_metrics.network.rxMbps // "N/A"' "$FILE1")
RX2=$(jq -r '.final_metrics.network.rxMbps // "N/A"' "$FILE2")
printf "%-25s | %-15s | %-15s | %-10s\n" "Network RX (Mbps)" "$RX1" "$RX2" "-"

# Network TX (if available)
TX1=$(jq -r '.final_metrics.network.txMbps // "N/A"' "$FILE1")
TX2=$(jq -r '.final_metrics.network.txMbps // "N/A"' "$FILE2")
printf "%-25s | %-15s | %-15s | %-10s\n" "Network TX (Mbps)" "$TX1" "$TX2" "-"

echo ""
echo "======================================"
echo " Summary"
echo "======================================"
echo ""
echo "📊 Full JSON comparison:"
echo "  diff <(jq . '$FILE1') <(jq . '$FILE2')"
echo ""
echo "💡 Tip: Lower is better for CPU, Memory, ELU, and Latency metrics"
echo "💡 Tip: Higher is better for Requests/sec throughput"
