#!/usr/bin/env bash
set -euo pipefail

VPS_URL="http://VPS_PUBLIC_IP:3000"
ENDPOINT="/metrics"

THREADS=4
DURATION="60s"
CONCURRENCY=(50 100 200 400 600 800 1000)
POLL_EVERY=2

echo "======================================"
echo " Auto-stop benchmark (ELU threshold)"
echo " Target: $VPS_URL$ENDPOINT"
echo "======================================"

for c in "${CONCURRENCY[@]}"; do
  echo ""
  echo ">>> Concurrency: $c"
  echo "--------------------------------------"

  wrk -t"$THREADS" -c"$c" -d"$DURATION" --latency "$VPS_URL$ENDPOINT" &
  WRK_PID=$!

  while kill -0 "$WRK_PID" 2>/dev/null; do
    sleep "$POLL_EVERY"

    # One request only (avoid double curl)
    JSON=$(curl -s "$VPS_URL/metrics" || true)
    if [[ -z "$JSON" ]]; then
      echo "Could not fetch /metrics (network?) continuing..."
      continue
    fi

    ELU=$(echo "$JSON" | jq -r '.eventLoop.elu.utilization')
    OVERLOADED=$(echo "$JSON" | jq -r '.eventLoop.overloaded')
    THRESH=$(echo "$JSON" | jq -r '.eventLoop.threshold')

    RX=$(echo "$JSON" | jq -r '.network.rxMbps // "null"')
    TX=$(echo "$JSON" | jq -r '.network.txMbps // "null"')

    echo "ELU=$ELU threshold=$THRESH overloaded=$OVERLOADED net(rxMbps=$RX txMbps=$TX)"

    if [[ "$OVERLOADED" == "true" ]]; then
      echo "🔥 ELU >= $THRESH — stopping test"
      kill -9 "$WRK_PID" || true
      wait "$WRK_PID" 2>/dev/null || true
      echo "SAFE MAX CAPACITY REACHED (previous step is your sustainable max)"
      exit 0
    fi
  done

  echo "Cooldown 15s..."
  sleep 15
done

echo "Benchmark completed without overload"
