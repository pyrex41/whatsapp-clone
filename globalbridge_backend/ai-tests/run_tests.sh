#!/bin/bash

# Translation API Test Runner
# Requires: curl, jq

set -e

TEST_FILE="translation_test_cases.json"
BASE_URL="http://localhost:4000"
PASSED=0
FAILED=0
TOTAL=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Translation API Test Runner${NC}"
echo -e "${BLUE}===========================${NC}"
echo ""

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed.${NC}"
    echo "Install with: brew install jq (macOS) or apt-get install jq (Ubuntu)"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is required but not installed.${NC}"
    exit 1
fi

# Check if test file exists
if [ ! -f "$TEST_FILE" ]; then
    echo -e "${RED}Error: Test file '$TEST_FILE' not found.${NC}"
    exit 1
fi

echo "Running tests against: $BASE_URL"
echo "Test file: $TEST_FILE"
echo ""

# Run each test
jq -c '.[]' "$TEST_FILE" | while read -r test_case; do
    TOTAL=$((TOTAL + 1))

    id=$(echo "$test_case" | jq -r '.id')
    description=$(echo "$test_case" | jq -r '.description')
    notes=$(echo "$test_case" | jq -r '.notes')

    echo -e "${YELLOW}Test $TOTAL: $id${NC}"
    echo "Description: $description"

    # Extract request details
    request_body=$(echo "$test_case" | jq '.request.body')

    # Make the request
    echo "Request: $(echo "$request_body" | jq -c '.')"
    response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "$BASE_URL/api/v1/ai/translate" \
        -H 'Content-Type: application/json' \
        -d "$request_body")

    # Split response and status
    response_body=$(echo "$response" | head -n -1)
    http_status=$(echo "$response" | tail -n 1 | cut -d: -f2)

    echo "HTTP Status: $http_status"
    echo "Response: $response_body"

    # Basic validation
    if [ "$http_status" -eq 200 ]; then
        if echo "$response_body" | jq -e '.success' >/dev/null 2>&1; then
            echo -e "${GREEN}✅ PASS: Success response received${NC}"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}❌ FAIL: Expected success response${NC}"
            FAILED=$((FAILED + 1))
        fi
    elif [ "$http_status" -eq 400 ] || [ "$http_status" -eq 422 ]; then
        if echo "$response_body" | jq -e '.error' >/dev/null 2>&1; then
            echo -e "${GREEN}✅ PASS: Expected error response${NC}"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}❌ FAIL: Expected error response${NC}"
            FAILED=$((FAILED + 1))
        fi
    elif [ "$http_status" -eq 429 ]; then
        echo -e "${YELLOW}⏳ RATE LIMITED: $response_body${NC}"
        echo "Waiting before next test..."
        retry_after=$(echo "$response_body" | jq -r '.retry_after_seconds // 60')
        sleep $retry_after
        TOTAL=$((TOTAL - 1))  # Don't count rate limited tests
        continue
    else
        echo -e "${RED}❌ FAIL: Unexpected HTTP status $http_status${NC}"
        FAILED=$((FAILED + 1))
    fi

    if [ -n "$notes" ] && [ "$notes" != "null" ]; then
        echo "Notes: $notes"
    fi

    echo "---"
    echo ""

    # Small delay to avoid overwhelming the API
    sleep 0.5
done

echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}============${NC}"
echo "Total Tests: $TOTAL"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
fi