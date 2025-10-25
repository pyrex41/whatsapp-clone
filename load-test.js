import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const bridgeMessageRate = new Trend('bridge_messages_per_second');
const apiResponseTime = new Trend('api_response_time');
const errorRate = new Rate('errors');

// Test configuration
export const options = {
  stages: [
    // Ramp up to 10 users over 30 seconds
    { duration: '30s', target: 10 },
    // Stay at 10 users for 1 minute
    { duration: '1m', target: 10 },
    // Ramp up to 50 users over 30 seconds
    { duration: '30s', target: 50 },
    // Stay at 50 users for 2 minutes
    { duration: '2m', target: 50 },
    // Ramp up to 100 users over 1 minute
    { duration: '1m', target: 100 },
    // Stay at 100 users for 3 minutes
    { duration: '3m', target: 100 },
    // Ramp down to 0 users over 30 seconds
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    // 95% of requests should be below 500ms
    http_req_duration: ['p(95)<500'],
    // Error rate should be below 1%
    errors: ['rate<0.01'],
    // Bridge message rate should be at least 10 messages/second under load
    'bridge_messages_per_second': ['avg>10'],
  },
};

// Base URL for the API
const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';

// Test data
const testUsers = [
  { email: 'test1@example.com', password: 'password123' },
  { email: 'test2@example.com', password: 'password123' },
  { email: 'test3@example.com', password: 'password123' },
];

let authTokens = [];
let threadIds = [];
let bridgeIds = [];

// Setup function - runs before the test starts
export function setup() {
  console.log('Setting up load test...');

  // Create test users and get auth tokens
  for (const user of testUsers) {
    const loginResponse = http.post(`${BASE_URL}/auth/login`, {
      email: user.email,
      password: user.password,
    });

    if (loginResponse.status === 200) {
      const token = loginResponse.json().token;
      authTokens.push(token);
      console.log(`Logged in user: ${user.email}`);
    } else {
      console.log(`Failed to login user: ${user.email}`);
    }
  }

  // Create test threads
  for (const token of authTokens) {
    const threadResponse = http.post(`${BASE_URL}/api/v1/threads`, {
      name: `Load Test Thread ${Date.now()}`,
      type: 'group',
    }, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    });

    if (threadResponse.status === 201) {
      const threadId = threadResponse.json().thread.id;
      threadIds.push(threadId);
      console.log(`Created thread: ${threadId}`);
    }
  }

  // Create test bridges
  for (const token of authTokens.slice(0, 2)) { // Only create bridges for first 2 users
    const bridgeResponse = http.post(`${BASE_URL}/api/v1/bridges`, {
      bridge_type: 'telegram',
      phone_number: '+1234567890',
    }, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    });

    if (bridgeResponse.status === 201) {
      const bridgeId = bridgeResponse.json().bridge.id;
      bridgeIds.push(bridgeId);
      console.log(`Created bridge: ${bridgeId}`);
    }
  }

  console.log(`Setup complete. Auth tokens: ${authTokens.length}, Threads: ${threadIds.length}, Bridges: ${bridgeIds.length}`);

  return { authTokens, threadIds, bridgeIds };
}

// Main test function
export default function (data) {
  const { authTokens, threadIds, bridgeIds } = data;

  // Pick a random auth token
  const token = authTokens[Math.floor(Math.random() * authTokens.length)];

  // Test 1: Health check
  const healthResponse = http.get(`${BASE_URL}/health`);
  check(healthResponse, {
    'health check status is 200': (r) => r.status === 200,
    'health check response time < 200ms': (r) => r.timings.duration < 200,
  }) || errorRate.add(1);

  // Test 2: Get user features
  const featuresResponse = http.get(`${BASE_URL}/api/features`, {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });
  check(featuresResponse, {
    'features status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  // Test 3: List threads
  const threadsResponse = http.get(`${BASE_URL}/api/v1/threads`, {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });
  check(threadsResponse, {
    'threads status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  // Test 4: Send a message (if we have threads)
  if (threadIds.length > 0) {
    const threadId = threadIds[Math.floor(Math.random() * threadIds.length)];
    const messageResponse = http.post(`${BASE_URL}/api/v1/threads/${threadId}/messages`, {
      content: `Load test message ${Date.now()}`,
      message_type: 'text',
    }, {
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
    });

    check(messageResponse, {
      'message send status is 201': (r) => r.status === 201,
    }) || errorRate.add(1);

    if (messageResponse.status === 201) {
      bridgeMessageRate.add(1);
    }
  }

  // Test 5: List bridges
  const bridgesResponse = http.get(`${BASE_URL}/api/v1/bridges`, {
    headers: {
      'Authorization': `Bearer ${token}`,
    },
  });
  check(bridgesResponse, {
    'bridges status is 200': (r) => r.status === 200,
  }) || errorRate.add(1);

  // Test 6: Bridge status polling (if we have bridges)
  if (bridgeIds.length > 0) {
    const bridgeId = bridgeIds[Math.floor(Math.random() * bridgeIds.length)];
    const bridgeResponse = http.get(`${BASE_URL}/api/v1/bridges/${bridgeId}`, {
      headers: {
        'Authorization': `Bearer ${token}`,
      },
    });
    check(bridgeResponse, {
      'bridge status is 200': (r) => r.status === 200,
    }) || errorRate.add(1);
  }

  // Test 7: AI endpoint (if available)
  const aiResponse = http.post(`${BASE_URL}/api/ai/summarize_thread`, {
    thread_id: threadIds[0] || 'test-thread',
    max_length: 100,
  }, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  });
  // AI endpoints might fail due to rate limits or feature flags, so we check but don't count as error
  check(aiResponse, {
    'AI response is reasonable': (r) => r.status === 200 || r.status === 429 || r.status === 403,
  });

  // Record API response time
  apiResponseTime.add(healthResponse.timings.duration);

  // Sleep for a random interval between 1-3 seconds
  sleep(Math.random() * 2 + 1);
}

// Teardown function - runs after the test completes
export function teardown(data) {
  console.log('Load test completed. Cleaning up...');

  const { authTokens, threadIds, bridgeIds } = data;

  // Clean up test data (optional - in production you might want to keep some data for analysis)
  // Note: This is commented out to avoid deleting data during actual load testing

  /*
  for (const token of authTokens) {
    for (const bridgeId of bridgeIds) {
      http.delete(`${BASE_URL}/api/v1/bridges/${bridgeId}`, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
    }
  }
  */

  console.log('Load test teardown complete.');
}