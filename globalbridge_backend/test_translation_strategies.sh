#!/bin/bash

# Translation Strategy Comparison Test Runner
# This script runs comprehensive tests comparing the two language detection strategies

set -e

echo "========================================"
echo "Translation Strategy Testing Suite"
echo "========================================"
echo ""

# Load environment variables from .env file
if [ -f .env ]; then
  echo "Loading environment variables from .env..."
  # Load .env, skip comments and empty lines, handle quotes properly
  set -a
  source <(grep -v '^#' .env | grep -v '^$' | sed 's/#.*//')
  set +a
else
  echo "⚠️  WARNING: .env file not found!"
  echo "    Create a .env file with your configuration."
  echo ""
fi

# API Key Configuration (edit this if not using .env)
# Uncomment and set your API key here if you prefer:
# export GROQ_API_KEY="your_groq_api_key_here"

# Check if GROQ_API_KEY is set
if [ -z "$GROQ_API_KEY" ]; then
  echo "⚠️  WARNING: GROQ_API_KEY is not set!"
  echo "    These tests require a valid Groq API key to make real API calls."
  echo "    Either:"
  echo "    1. Add GROQ_API_KEY to your .env file, or"
  echo "    2. Uncomment and edit the GROQ_API_KEY line in this script"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

echo "Test Configuration:"
echo "  GROQ_API_KEY: ${GROQ_API_KEY:0:10}..."
echo "  GROQ_MODEL: ${GROQ_MODEL:-llama-3.3-70b-versatile (default)}"
echo "  LANGUAGE_DETECTION_STRATEGY: ${LANGUAGE_DETECTION_STRATEGY:-dedicated (default)}"
echo "  SQLITE_VEC_PATH: ${SQLITE_VEC_PATH:-not set}"
echo ""

# Run different test suites
echo "========================================"
echo "1. Unit Tests (Fast)"
echo "========================================"
echo ""
mix test test/globalbridge_backend/ai/language_detection_service_test.exs
mix test test/globalbridge_backend_web/validators/ai_validator_test.exs

echo ""
echo "========================================"
echo "2. Controller Integration Tests"
echo "========================================"
echo ""
mix test test/globalbridge_backend_web/controllers/ai_controller_test.exs

echo ""
echo "========================================"
echo "3. Strategy Comparison Tests (Slow)"
echo "========================================"
echo "NOTE: These tests make real API calls and will take 2-5 minutes"
echo ""
read -p "Run comprehensive strategy comparison tests? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "Running performance comparison..."
  mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include integration --include performance

  echo ""
  echo "Running accuracy comparison..."
  mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include integration --include accuracy

  echo ""
  echo "Running cost analysis..."
  mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include integration --include cost

  echo ""
  echo "Running edge case tests..."
  mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include integration --include edge_cases
fi

echo ""
echo "========================================"
echo "✅ Test Suite Complete!"
echo "========================================"
echo ""
echo "Next Steps:"
echo "  1. Review the performance metrics printed above"
echo "  2. Compare latency between combined vs dedicated strategies"
echo "  3. Check accuracy results for different languages"
echo "  4. Set LANGUAGE_DETECTION_STRATEGY based on your needs:"
echo "     export LANGUAGE_DETECTION_STRATEGY=combined    # Fast, good accuracy"
echo "     export LANGUAGE_DETECTION_STRATEGY=dedicated   # Slower, best accuracy"
echo ""
