# Testing Translation Strategies - Complete Guide

## Overview

This guide explains how to test and compare the two language detection strategies using the comprehensive test suite.

---

## Test Files Created

### 1. **Unit Tests**

#### `test/globalbridge_backend/ai/language_detection_service_test.exs`
- Tests language code ↔ name mapping
- Tests strategy configuration
- Integration tests for both detection strategies
- ~30 test cases

#### `test/globalbridge_backend_web/validators/ai_validator_test.exs`
- Updated with tests for `validate_optional_target_language/1`
- Validates nil handling for auto-detection
- Language code validation

### 2. **Integration Tests**

#### `test/globalbridge_backend_web/controllers/ai_controller_test.exs`
- Updated translation tests with new response fields
- Tests for both detection strategies
- Performance timing measurements
- Idiom detection tests

#### `test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs`
- **Comprehensive strategy comparison suite**
- Performance benchmarking
- Accuracy testing across 11 languages
- Cost analysis
- Edge case handling
- ~15 test scenarios

---

## Quick Start

### Prerequisites

```bash
# Required: Set your Groq API key
export GROQ_API_KEY=your_groq_api_key_here

# Optional: Set default strategy
export LANGUAGE_DETECTION_STRATEGY=combined  # or "dedicated"

# Optional: Set model
export GROQ_MODEL=llama-3.3-70b-versatile
```

### Run All Tests

```bash
# Navigate to backend directory
cd globalbridge_backend

# Run the test script
./test_translation_strategies.sh
```

### Run Specific Test Suites

```bash
# Unit tests only (fast, no API calls)
mix test test/globalbridge_backend/ai/language_detection_service_test.exs --exclude integration

# Integration tests (requires API key)
mix test test/globalbridge_backend/ai/language_detection_service_test.exs --include integration

# Controller tests
mix test test/globalbridge_backend_web/controllers/ai_controller_test.exs

# Strategy comparison (comprehensive)
mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include integration
```

---

## Test Categories

### 1. Performance Tests

**File:** `ai_translation_strategy_test.exs`
**Tag:** `@tag :performance`

**What it tests:**
- Latency comparison between strategies
- Multiple languages (Spanish, French, German, Japanese)
- Measures actual milliseconds for each strategy
- Prints detailed performance table

**Run:**
```bash
mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include performance
```

**Expected Output:**
```
================================================================================
STRATEGY PERFORMANCE COMPARISON
================================================================================

Testing text: "Hola mundo" (Expected: Spanish)
--------------------------------------------------------------------------------
  Combined (1523ms): Spanish → Hello world
  Dedicated (2341ms): Spanish → Hello world

Testing text: "Bonjour le monde" (Expected: French)
--------------------------------------------------------------------------------
  Combined (1487ms): French → Hello world
  Dedicated (2298ms): French → Hello world

================================================================================
SUMMARY
================================================================================

Text                      | Strategy   | Detected   | Latency    | Confidence
--------------------------------------------------------------------------------
Hola mundo                | Combined   | Spanish    | 1523ms     | 0.98
                          | Dedicated  | Spanish    | 2341ms     | 0.97

Bonjour le monde          | Combined   | French     | 1487ms     | 0.99
                          | Dedicated  | French     | 2298ms     | 0.98
```

### 2. Accuracy Tests

**File:** `ai_translation_strategy_test.exs`
**Tag:** `@tag :accuracy`

**What it tests:**
- Detection accuracy for 11 languages
- Compares both strategies on same texts
- Calculates accuracy percentage
- Identifies which languages each strategy handles best

**Run:**
```bash
mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include accuracy
```

**Expected Output:**
```
================================================================================
LANGUAGE DETECTION ACCURACY TEST
================================================================================

Testing: Spanish (es)
  Combined: es ✓
  Dedicated: es ✓

Testing: French (fr)
  Combined: fr ✓
  Dedicated: fr ✓

Testing: Japanese (ja)
  Combined: ja ✓
  Dedicated: ja ✓

...

================================================================================
ACCURACY RESULTS
================================================================================
Combined Strategy:  90.9% correct
Dedicated Strategy: 100.0% correct
================================================================================
```

### 3. Cost Analysis

**File:** `ai_translation_strategy_test.exs`
**Tag:** `@tag :cost`

**What it tests:**
- Token usage estimates
- Cost comparison between strategies
- API call count

**Run:**
```bash
mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include cost
```

**Expected Output:**
```
================================================================================
COST ANALYSIS
================================================================================

Text: "Hola, ¿cómo estás hoy? Espero que todo esté bien."

Combined Strategy:
  Estimated tokens: ~150
  Estimated cost: $0.000030/1M tokens
  API calls: 1

Dedicated Strategy:
  Estimated tokens: ~250
  Estimated cost: $0.000050/1M tokens
  API calls: 2

Cost difference: ~66.7% more expensive for dedicated
================================================================================
```

### 4. Edge Cases

**File:** `ai_translation_strategy_test.exs`
**Tag:** `@tag :edge_cases`

**What it tests:**
- Very short text
- Mixed language text
- Text with emojis
- Text with numbers
- Consistency across strategies

**Run:**
```bash
mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include edge_cases
```

---

## Interpreting Test Results

### Performance Metrics

**What to look for:**
- **Latency difference**: Is combined consistently faster?
- **Typical range**:
  - Combined: 1.5-2 seconds
  - Dedicated: 2-3 seconds
- **Variance**: Are timings consistent or fluctuating?

**Decision criteria:**
- If combined is 30-50% faster → Prefer combined for production
- If dedicated latency is acceptable → Consider accuracy benefits

### Accuracy Metrics

**What to look for:**
- **Overall accuracy**: Both should be >90%
- **Language-specific**: Which languages cause issues?
- **Consistency**: Are mistakes consistent or random?

**Decision criteria:**
- If both strategies have similar accuracy → Choose combined (faster)
- If dedicated is significantly better → Worth the extra latency
- If specific languages fail → May need prompt improvements

### Cost Analysis

**What to look for:**
- Token usage difference between strategies
- Cost per translation (usually $0.00002-0.00005)
- At scale: 1M translations = $20-50

**Decision criteria:**
- Cost difference is usually small (~50-70%)
- Performance/accuracy usually outweigh marginal cost difference

---

## Running Tests in CI/CD

### GitHub Actions Example

```yaml
name: Translation Strategy Tests

on: [pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    env:
      GROQ_API_KEY: ${{ secrets.GROQ_API_KEY }}
      LANGUAGE_DETECTION_STRATEGY: combined

    steps:
      - uses: actions/checkout@v2

      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'

      - name: Install dependencies
        run: mix deps.get
        working-directory: ./globalbridge_backend

      - name: Run unit tests
        run: mix test --exclude integration
        working-directory: ./globalbridge_backend

      - name: Run integration tests (if API key available)
        if: ${{ secrets.GROQ_API_KEY != '' }}
        run: |
          mix test test/globalbridge_backend_web/controllers/ai_controller_test.exs
          mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include integration --include performance
        working-directory: ./globalbridge_backend
```

---

## Test Data & Examples

### Sample Test Texts by Language

```elixir
# Spanish
"Hola, ¿cómo estás?"
"Me encanta programar en Elixir"
"Buenos días, ¿qué tal?"

# French
"Bonjour, comment allez-vous?"
"J'aime la programmation"
"Bonne journée!"

# German
"Guten Tag, wie geht es Ihnen?"
"Ich liebe das Programmieren"
"Schönen Tag noch!"

# Japanese
"こんにちは、お元気ですか？"
"プログラミングが大好きです"
"良い一日を！"

# Chinese
"你好，你好吗？"
"我喜欢编程"
"祝你有美好的一天！"
```

### Test Scenarios

#### Scenario 1: Common Language (Spanish)
- **Expected behavior**: Both strategies should detect correctly
- **Performance**: Combined should be faster
- **Accuracy**: Both should be 100%

#### Scenario 2: Complex Script (Japanese)
- **Expected behavior**: May challenge detection
- **Performance**: Both may take longer
- **Accuracy**: Dedicated might be more accurate

#### Scenario 3: Mixed Language
- **Expected behavior**: Should detect dominant language
- **Performance**: Normal latency
- **Accuracy**: May vary

---

## Troubleshooting

### Issue: Tests timing out

**Cause:** Groq API is slow or rate-limited

**Solution:**
```bash
# Increase timeout
mix test --timeout 120000

# Or in test file:
@tag timeout: 120_000
```

### Issue: API key errors

**Cause:** GROQ_API_KEY not set

**Solution:**
```bash
export GROQ_API_KEY=your_key_here
mix test
```

### Issue: Rate limit errors

**Cause:** Too many requests

**Solution:**
```bash
# The tests include :timer.sleep(1000) delays
# If still hitting limits, increase delays in test file
:timer.sleep(2000)  # 2 second delay between tests
```

### Issue: Inconsistent results

**Cause:** LLM non-determinism

**Solution:**
- Run tests multiple times
- Look for trends, not single results
- Check if temperature setting is low (0.1-0.3)

---

## Best Practices

### 1. Run Tests Multiple Times

```bash
# Run 3 times and compare
for i in {1..3}; do
  echo "Run $i"
  mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include performance
done
```

### 2. Test Different Languages

Focus on languages your users actually use:
```elixir
# Add your user's languages to test_cases
test_cases = [
  %{text: "Your language 1", expected_code: "xx", name: "Language 1"},
  %{text: "Your language 2", expected_code: "yy", name: "Language 2"},
]
```

### 3. Monitor Production Metrics

After deploying, track:
- Average latency per strategy
- Detection accuracy (user corrections)
- Cost per translation
- User satisfaction

---

## Continuous Testing

### Weekly Regression Tests

```bash
#!/bin/bash
# weekly_translation_test.sh

echo "Weekly Translation Strategy Test - $(date)"

# Test both strategies
export LANGUAGE_DETECTION_STRATEGY=combined
mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include performance > combined_results.txt

export LANGUAGE_DETECTION_STRATEGY=dedicated
mix test test/globalbridge_backend_web/controllers/ai_translation_strategy_test.exs --include performance > dedicated_results.txt

# Compare results
echo "Results saved to combined_results.txt and dedicated_results.txt"
```

---

## What to Report

After running tests, report:

1. **Performance Summary**
   - Average latency for each strategy
   - Latency variance

2. **Accuracy Summary**
   - Overall accuracy percentage
   - Per-language accuracy
   - Failure cases

3. **Cost Summary**
   - Estimated cost per 1000 translations
   - Monthly cost projection

4. **Recommendation**
   - Which strategy to use by default
   - When to use the other strategy
   - Any prompt improvements needed

---

## Example Test Report

```markdown
# Translation Strategy Test Report

Date: 2024-01-15
Tester: [Your Name]

## Test Configuration
- API: Groq llama-3.3-70b-versatile
- Languages tested: 11
- Test runs: 3

## Results

### Performance
- Combined avg: 1,547ms (±143ms)
- Dedicated avg: 2,312ms (±198ms)
- Combined is 33% faster

### Accuracy
- Combined: 90.9% correct (10/11 languages)
- Dedicated: 100% correct (11/11 languages)
- Failed language for combined: Arabic

### Cost
- Combined: $0.000025 per translation
- Dedicated: $0.000040 per translation
- Dedicated is 60% more expensive

## Recommendation

**Use Combined as default:**
- 33% faster
- 90% accuracy is acceptable
- Lower cost
- Good for common languages

**Use Dedicated for:**
- Arabic translations (failed in combined)
- Critical translations requiring highest accuracy
- When latency is not a concern
```

---

## Next Steps After Testing

1. **Choose Default Strategy**
   ```bash
   # In production .env
   export LANGUAGE_DETECTION_STRATEGY=combined
   ```

2. **Monitor in Production**
   - Track actual latency
   - Monitor user corrections (indicates accuracy issues)
   - Watch API costs

3. **Iterate**
   - Adjust prompts based on failures
   - Add more test cases
   - Fine-tune temperature settings

4. **Document Decision**
   - Update team docs with chosen strategy
   - Document trade-offs
   - Set review schedule (quarterly?)

---

## Support & Questions

- **Test failures**: Check `test_translation_strategies.sh` script
- **API issues**: Verify GROQ_API_KEY is set correctly
- **Performance issues**: Consider using mocks for unit tests
- **Strategy questions**: Review docs/translation_endpoint_guide.md
