# Load Testing Guide

This document describes the load testing setup for GlobalBridge to ensure the system can handle concurrent bridge operations and API requests under various load conditions.

## Prerequisites

1. **k6** - Load testing tool
   ```bash
   # Install k6 (macOS with Homebrew)
   brew install k6

   # Or download from https://k6.io/docs/get-started/installation/
   ```

2. **Running Backend** - Ensure the backend is running locally or on a test environment
   ```bash
   cd globalbridge_backend
   mix phx.server
   ```

3. **Test Data** - The load test will create its own test users, threads, and bridges during setup

## Running Load Tests

### Basic Load Test

```bash
# Run against local development server
k6 run load-test.js

# Run against staging environment
k6 run -e BASE_URL=https://staging-api.globalbridge.com load-test.js

# Run with custom options
k6 run --vus 10 --duration 30s load-test.js
```

### Load Test Scenarios

The load test includes several scenarios:

1. **Health Checks** - Continuous monitoring of system health
2. **API Endpoints** - Testing core API functionality
3. **Bridge Operations** - Creating and monitoring bridges
4. **Message Operations** - Sending messages through threads
5. **AI Features** - Testing AI-powered features (when available)

### Test Configuration

The load test is configured with the following stages:

- **Ramp Up**: 0 → 10 users over 30 seconds
- **Baseline**: 10 users for 1 minute
- **Medium Load**: 10 → 50 users over 30 seconds
- **Sustained Load**: 50 users for 2 minutes
- **High Load**: 50 → 100 users over 1 minute
- **Peak Load**: 100 users for 3 minutes
- **Ramp Down**: 100 → 0 users over 30 seconds

### Performance Thresholds

The test validates the following performance criteria:

- **Response Time**: 95% of requests < 500ms
- **Error Rate**: < 1% error rate
- **Message Throughput**: > 10 bridge messages/second under load
- **System Stability**: No crashes or memory leaks

## Monitoring During Load Tests

### Backend Metrics

Monitor the following during load testing:

```bash
# Phoenix metrics
curl http://localhost:4000/health

# Database connections
# Check PostgreSQL connection pool usage

# Bridge telemetry
# Monitor bridge connection status and message rates
```

### System Resources

```bash
# CPU and memory usage
top -l 1

# Network I/O
netstat -i

# Disk I/O
iostat -d 1
```

## Interpreting Results

### Success Criteria

- All HTTP requests return 2xx or expected status codes
- Response times stay within thresholds
- Error rate remains below 1%
- System remains stable (no crashes, memory leaks)
- Bridge operations complete successfully

### Common Issues

1. **Database Connection Pool Exhausted**
   - Increase database pool size in config
   - Optimize database queries

2. **High Response Times**
   - Check database query performance
   - Review Phoenix endpoint optimizations
   - Consider caching strategies

3. **Bridge Connection Failures**
   - Verify external API rate limits
   - Check network connectivity
   - Review bridge error handling

## Load Test Customization

### Modifying Test Scenarios

Edit `load-test.js` to customize:

```javascript
export const options = {
  stages: [
    // Customize stages as needed
    { duration: '1m', target: 20 },  // 1 minute ramp to 20 users
    { duration: '5m', target: 20 },  // 5 minutes at 20 users
  ],
  thresholds: {
    // Adjust thresholds based on requirements
    http_req_duration: ['p(95)<1000'],  // Allow 1 second for 95% of requests
  },
};
```

### Adding New Test Cases

Add new test functions to `load-test.js`:

```javascript
// Test bridge webhook simulation
function testBridgeWebhook() {
  const webhookResponse = http.post(`${BASE_URL}/api/webhooks/telegram`, {
    update_id: Date.now(),
    message: { text: 'Webhook test' }
  });

  check(webhookResponse, {
    'webhook processed': (r) => r.status === 200,
  });
}
```

## CI/CD Integration

Load tests are automatically run in the CI/CD pipeline defined in `.github/workflows/ci.yml`. The pipeline includes:

- Unit tests for all components
- Integration tests for bridge functionality
- Load tests with configurable thresholds
- Performance regression detection

## Troubleshooting

### Common Load Test Issues

1. **k6 Installation Issues**
   ```bash
   # Check k6 version
   k6 version

   # Reinstall if needed
   brew reinstall k6
   ```

2. **Backend Not Responding**
   ```bash
   # Check if backend is running
   curl http://localhost:4000/health

   # Check backend logs
   tail -f globalbridge_backend/logs/*.log
   ```

3. **Database Connection Issues**
   ```bash
   # Check database connectivity
   psql -h localhost -U postgres -d globalbridge_test -c "SELECT 1"

   # Check connection pool
   # Monitor Phoenix database metrics
   ```

### Performance Optimization

Based on load test results, consider these optimizations:

1. **Database Indexing**
   - Add indexes on frequently queried columns
   - Optimize complex queries

2. **Caching**
   - Implement Redis for session storage
   - Cache frequently accessed data

3. **Connection Pooling**
   - Increase database connection pool size
   - Configure Phoenix connection pooling

4. **Async Processing**
   - Move heavy operations to background jobs
   - Implement message queuing for bridge operations

## Next Steps

After successful load testing:

1. **Deploy to Staging** - Deploy tested code to staging environment
2. **Monitor Production** - Set up production monitoring and alerting
3. **Performance Tuning** - Continuously optimize based on real-world usage
4. **Capacity Planning** - Plan for future growth based on load test insights