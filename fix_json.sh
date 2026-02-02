#!/usr/bin/env bash
# Script to fix broken JSON files with control characters
# Usage: ./fix_json.sh <broken_file.json> <output_file.json>

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <broken_file.json> <output_file.json>"
  exit 1
fi

INPUT="$1"
OUTPUT="$2"

if [ ! -f "$INPUT" ]; then
  echo "Error: File not found: $INPUT"
  exit 1
fi

echo "Fixing JSON file: $INPUT"
echo "Output: $OUTPUT"

# Fix the specific issue with wrk_latency fields containing newlines
# Pattern: "wrk_latency_avg": "XXms<newline>Distribution"
# Replace with: "wrk_latency_avg": "XXms"

# Read file, fix multi-line string values in wrk fields
python3 << 'PYEOF' > "$OUTPUT"
import sys
import json
import re

with open(sys.argv[1], 'r') as f:
    content = f.read()

# Fix the specific pattern: "valueDistribution" with newline in between
# This happens in wrk_latency_avg and wrk_latency_p95 fields
content = re.sub(r'("\w+ms)\s*\n\s*Distribution(")', r'\1\2', content)

# Remove Distribution word if it appears after ms
content = re.sub(r'("\w+ms)Distribution(")', r'\1\2', content)

# Print the fixed content
print(content, end='')
PYEOF

python3 "$OUTPUT" "$INPUT"

# Validate the output
if jq empty "$OUTPUT" 2>/dev/null; then
  echo "✅ Fixed! Validation passed."
  echo ""
  echo "Test it:"
  echo "  jq . $OUTPUT | head -20"
  echo ""
  echo "Compare VPS:"
  echo "  ./compare_results.sh $OUTPUT <other_file.json>"
else
  echo "❌ Still invalid. Trying alternative method..."
  
  # Alternative: manually reconstruct by removing newlines in specific fields
  sed ':a;N;$!ba;s/"wrk_latency_avg": "\([^"]*\)\nDistribution"/"wrk_latency_avg": "\1"/g;s/"wrk_latency_p95": "\([^"]*\)\nDistribution"/"wrk_latency_p95": "\1"/g' "$INPUT" > "$OUTPUT"
  
  if jq empty "$OUTPUT" 2>/dev/null; then
    echo "✅ Fixed with alternative method!"
  else
    echo "❌ Still invalid. Manual edit required."
    echo ""
    echo "The issue is in these lines - they have literal newlines:"
    grep -n "Distribution" "$INPUT" | head -5
  fi
fi

