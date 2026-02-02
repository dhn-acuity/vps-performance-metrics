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

# Remove control characters and fix multi-line strings in JSON
# This replaces newlines within string values with \n
sed ':a;N;$!ba;s/"\([^"]*\)\n\([^"]*\)"/"\1\\n\2"/g' "$INPUT" | \
  tr -d '\000-\010\013\014\016-\037' > "$OUTPUT"

# Validate the output
if jq empty "$OUTPUT" 2>/dev/null; then
  echo "✅ Fixed! Validation passed."
  echo ""
  echo "Test it:"
  echo "  jq . $OUTPUT | head -20"
else
  echo "❌ Still invalid. Manual inspection needed."
  echo ""
  echo "Try viewing problematic lines:"
  echo "  cat -A $INPUT | grep -n '\^M\|\^J' | head -20"
fi
