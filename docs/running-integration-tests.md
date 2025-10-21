# Running Integration Tests - Quick Reference

## Overview
Comprehensive integration tests for Tasks 13, 14, and 16 covering CDC triggers, sync endpoints, and offline queue functionality.

---

## iOS Tests (XCTest Framework)

### Prerequisites
```bash
# Ensure you're in the iOS project directory
cd clients/ios/GlobalBridge

# Install dependencies (if using SPM)
xcodebuild -resolvePackageDependencies
```

### Running CDC Trigger Tests

```bash
# Run all CDC trigger tests
xcodebuild test \
  -project GlobalBridge.xcodeproj \
  -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GlobalBridgeTests/CDCTriggerTests

# Run specific test
xcodebuild test \
  -project GlobalBridge.xcodeproj \
  -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GlobalBridgeTests/CDCTriggerTests/testCDCTriggerFiresOnMessageInsert
```

### Running Offline Sync Integration Tests

```bash
# Run all offline sync tests
xcodebuild test \
  -project GlobalBridge.xcodeproj \
  -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GlobalBridgeTests/OfflineSyncIntegrationTests

# Run specific test
xcodebuild test \
  -project GlobalBridge.xcodeproj \
  -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GlobalBridgeTests/OfflineSyncIntegrationTests/testOfflineMessageToQueueToSyncToServer
```

### Using Xcode IDE

1. Open `GlobalBridge.xcodeproj` in Xcode
2. Press `⌘ + U` to run all tests
3. Or press `⌘ + 6` to open Test Navigator
4. Click the diamond next to specific test classes or methods

---

## Phoenix Tests (ExUnit Framework)

### Prerequisites
```bash
# Navigate to backend directory
cd globalbridge_backend

# Install dependencies
mix deps.get

# Setup test database
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

### Running Sync Controller Tests

```bash
# Run all sync controller tests
mix test test/globalbridge_backend_web/controllers/sync_controller_test.exs

# Run with verbose output
mix test test/globalbridge_backend_web/controllers/sync_controller_test.exs --trace

# Run specific test
mix test test/globalbridge_backend_web/controllers/sync_controller_test.exs:40

# Run specific describe block
mix test test/globalbridge_backend_web/controllers/sync_controller_test.exs --only describe:"GET /api/v1/sync/pull"
```

### Running with Coverage

```bash
# Generate coverage report
mix test --cover test/globalbridge_backend_web/controllers/sync_controller_test.exs

# Coverage report will be in cover/excoveralls.html
open cover/excoveralls.html
```

### Running Tagged Tests

```bash
# Run only integration tests
mix test --only integration

# Exclude integration tests
mix test --exclude integration
```

---

## Continuous Integration

### GitHub Actions Example

```yaml
# .github/workflows/tests.yml
name: Integration Tests

on: [push, pull_request]

jobs:
  ios-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run iOS Tests
        run: |
          cd clients/ios/GlobalBridge
          xcodebuild test \
            -project GlobalBridge.xcodeproj \
            -scheme GlobalBridge \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -only-testing:GlobalBridgeTests/CDCTriggerTests \
            -only-testing:GlobalBridgeTests/OfflineSyncIntegrationTests

  phoenix-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          otp-version: '26'
          elixir-version: '1.15'
      - name: Run Phoenix Tests
        run: |
          cd globalbridge_backend
          mix deps.get
          MIX_ENV=test mix ecto.create
          MIX_ENV=test mix ecto.migrate
          mix test test/globalbridge_backend_web/controllers/sync_controller_test.exs
```

---

## Test Output Examples

### Successful iOS Test
```
Test Suite 'CDCTriggerTests' started at 2025-10-20 23:26:45.123
Test Case '-[GlobalBridgeTests.CDCTriggerTests testCDCTriggerFiresOnMessageInsert]' started.
✅ Thread created: 12345-67890
✅ Message created: 98765-43210
✅ CDC event logged: insert on messages
Test Case '-[GlobalBridgeTests.CDCTriggerTests testCDCTriggerFiresOnMessageInsert]' passed (0.234 seconds).

Executed 13 tests, with 0 failures (0 unexpected) in 3.456 (3.678) seconds
```

### Successful Phoenix Test
```
...............

Finished in 2.4 seconds (1.2s async, 1.2s sync)
20 tests, 0 failures

Randomized with seed 123456
```

---

## Debugging Failed Tests

### iOS Test Debugging

```bash
# Enable detailed logging
export XCODE_DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test ... -enableCodeCoverage YES

# View crash logs
open ~/Library/Developer/Xcode/DerivedData

# Debug specific test in console
lldb -- xcrun simctl spawn booted /path/to/test
```

### Phoenix Test Debugging

```bash
# Run with IEx for debugging
iex -S mix test test/globalbridge_backend_web/controllers/sync_controller_test.exs

# Add IO.inspect in test file
IO.inspect(response, label: "Response")

# Enable query logging
config :logger, level: :debug
```

---

## Performance Profiling

### iOS - Instruments

```bash
# Run with performance profiling
xcodebuild test \
  -project GlobalBridge.xcodeproj \
  -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:GlobalBridgeTests/CDCTriggerTests/testCDCTriggersDoNotSlowDownInsertOperations \
  -enableCodeCoverage YES \
  -resultBundlePath ./TestResults

# Open in Instruments
open ./TestResults.xcresult
```

### Phoenix - Benchee

```elixir
# Add to test file for benchmarking
Benchee.run(%{
  "sync_push_100" => fn ->
    # Your test code
  end
})
```

---

## Test Data Cleanup

### iOS
```swift
// Automatic in setUp/tearDown
override func tearDown() async throws {
    try? await databaseManager.deleteThread(id: thread.id)
    databaseManager.closeAllConnections()
}
```

### Phoenix
```elixir
# Automatic with Ecto Sandbox
setup tags do
  :ok = Ecto.Adapters.SQL.Sandbox.checkout(GlobalbridgeBackend.Repo)
  unless tags[:async] do
    Ecto.Adapters.SQL.Sandbox.mode(GlobalbridgeBackend.Repo, {:shared, self()})
  end
  :ok
end
```

---

## Common Issues & Solutions

### Issue: iOS Tests Can't Find DatabaseManager
```bash
# Solution: Rebuild dependencies
cd clients/ios/GlobalBridge
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodebuild clean
xcodebuild build -project GlobalBridge.xcodeproj -scheme GlobalBridge
```

### Issue: Phoenix Tests Database Connection Error
```bash
# Solution: Reset test database
MIX_ENV=test mix ecto.drop
MIX_ENV=test mix ecto.create
MIX_ENV=test mix ecto.migrate
```

### Issue: CDC Triggers Not Firing
```bash
# Check SQLite pragma
sqlite3 globalbridge_main.db "PRAGMA foreign_keys;"
# Should return: 1

# Check WAL mode
sqlite3 globalbridge_main.db "PRAGMA journal_mode;"
# Should return: wal
```

---

## Test Metrics

### Expected Performance
- **CDC Insert**: < 20ms per operation
- **CDC Update**: < 15ms per operation
- **Sync Pull**: < 100ms for 100 items
- **Sync Push**: < 5s for 500 items
- **Offline Queue**: < 50ms per enqueue

### Coverage Targets
- Statement Coverage: > 90%
- Branch Coverage: > 85%
- Function Coverage: > 90%

---

## Next Steps

1. **Run all tests**: Verify current implementation
2. **Check coverage**: Ensure 90%+ coverage
3. **Profile performance**: Validate benchmarks
4. **Fix failures**: Address any implementation gaps
5. **Add E2E tests**: Real server + client integration

---

*Quick Reference Guide - Task Master AI System*
*Last Updated: 2025-10-20*
