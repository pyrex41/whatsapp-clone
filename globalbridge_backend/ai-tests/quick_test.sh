#!/bin/bash

# Quick Translation API Test Script
# Usage: ./quick_test.sh [test_name]
# Example: ./quick_test.sh basic_english_to_spanish

BASE_URL="http://localhost:4000"
EXAMPLES_FILE="example_requests.json"

if [ $# -eq 0 ]; then
    echo "Usage: $0 <test_name>"
    echo ""
    echo "Available tests:"
    jq -r 'keys[]' "$EXAMPLES_FILE" | sed 's/^/  - /'
    exit 1
fi

TEST_NAME="$1"

# Check if test exists
if ! jq -e "has(\"$TEST_NAME\")" "$EXAMPLES_FILE" >/dev/null; then
    echo "Error: Test '$TEST_NAME' not found."
    echo ""
    echo "Available tests:"
    jq -r 'keys[]' "$EXAMPLES_FILE" | sed 's/^/  - /'
    exit 1
fi

echo "Running test: $TEST_NAME"
echo "Request body:"
jq ".$TEST_NAME" "$EXAMPLES_FILE"
echo ""

echo "Response:"
curl -X POST "$BASE_URL/api/v1/ai/translate" \
  -H 'Content-Type: application/json' \
  -d "$(jq -c ".$TEST_NAME" "$EXAMPLES_FILE")"

echo ""