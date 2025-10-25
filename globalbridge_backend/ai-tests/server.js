#!/usr/bin/env node

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 3030;
const TEST_FILE = path.join(__dirname, 'translation_test_cases.json');

// Read test cases
let testCases = [];
try {
  testCases = JSON.parse(fs.readFileSync(TEST_FILE, 'utf8'));
} catch (error) {
  console.error('Error loading test cases:', error.message);
  process.exit(1);
}

// Simple HTTP server
const server = http.createServer(async (req, res) => {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }

  // Serve the main HTML page
  if (req.url === '/' || req.url === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(getHTML());
    return;
  }

  // API: Get all test cases
  if (req.url === '/api/tests' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(testCases));
    return;
  }

  // API: Run a specific test
  if (req.url.startsWith('/api/run/') && req.method === 'POST') {
    const testId = req.url.split('/api/run/')[1];
    const test = testCases.find(t => t.id === testId);

    if (!test) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Test not found' }));
      return;
    }

    try {
      const result = await runTest(test);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(result));
    } catch (error) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: error.message }));
    }
    return;
  }

  // 404
  res.writeHead(404);
  res.end('Not found');
});

// Run a single test
async function runTest(test) {
  const startTime = Date.now();

  try {
    const response = await fetch(test.request.url, {
      method: test.request.method,
      headers: test.request.headers,
      body: JSON.stringify(test.request.body)
    });

    const responseTime = Date.now() - startTime;
    const data = await response.json();

    // Compare with expected results
    const passed = compareResults(data, test.expected);

    return {
      testId: test.id,
      passed,
      response: data,
      expected: test.expected,
      statusCode: response.status,
      responseTime,
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    return {
      testId: test.id,
      passed: false,
      error: error.message,
      responseTime: Date.now() - startTime,
      timestamp: new Date().toISOString()
    };
  }
}

// Compare actual response with expected
function compareResults(actual, expected) {
  // If expected has an error field, check if actual has that error
  if (expected.error) {
    return actual.error && actual.error.includes(expected.error);
  }

  // Check success field
  if (expected.success !== undefined && actual.success !== expected.success) {
    return false;
  }

  // Check if hasCulturalNotes is specified
  if (expected.hasCulturalNotes !== undefined) {
    const hasNotes = actual.cultural_notes && actual.cultural_notes.length > 0;
    if (hasNotes !== expected.hasCulturalNotes) {
      return false;
    }
  }

  // Check confidence threshold (allow some variance)
  if (expected.confidence !== undefined) {
    if (!actual.confidence || actual.confidence < expected.confidence - 0.1) {
      return false;
    }
  }

  // Check languages
  if (expected.source_language && actual.source_language) {
    if (!actual.source_language.toLowerCase().includes(expected.source_language.toLowerCase()) &&
        !expected.source_language.toLowerCase().includes(actual.source_language.toLowerCase())) {
      return false;
    }
  }

  if (expected.target_language && actual.target_language !== expected.target_language) {
    return false;
  }

  // If translation is expected, just check it exists (not exact match due to LLM variation)
  if (expected.translation !== undefined && !actual.translation) {
    return false;
  }

  return true;
}

// Generate HTML page
function getHTML() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Translation API Test Runner</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f5f5f5;
      padding: 20px;
      line-height: 1.6;
    }
    .container {
      max-width: 1400px;
      margin: 0 auto;
      background: white;
      border-radius: 8px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
      overflow: hidden;
    }
    .header {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white;
      padding: 30px;
    }
    .header h1 {
      font-size: 28px;
      margin-bottom: 10px;
    }
    .header p {
      opacity: 0.9;
      font-size: 14px;
    }
    .controls {
      padding: 20px 30px;
      background: #f8f9fa;
      border-bottom: 1px solid #e0e0e0;
      display: flex;
      gap: 15px;
      align-items: center;
      flex-wrap: wrap;
    }
    .btn {
      padding: 10px 20px;
      border: none;
      border-radius: 6px;
      cursor: pointer;
      font-size: 14px;
      font-weight: 600;
      transition: all 0.2s;
    }
    .btn-primary {
      background: #667eea;
      color: white;
    }
    .btn-primary:hover {
      background: #5568d3;
      transform: translateY(-1px);
      box-shadow: 0 4px 8px rgba(102, 126, 234, 0.3);
    }
    .btn-secondary {
      background: #48bb78;
      color: white;
    }
    .btn-secondary:hover {
      background: #38a169;
    }
    .btn-danger {
      background: #f56565;
      color: white;
    }
    .btn-danger:hover {
      background: #e53e3e;
    }
    .btn:disabled {
      opacity: 0.5;
      cursor: not-allowed;
      transform: none;
    }
    .stats {
      display: flex;
      gap: 20px;
      margin-left: auto;
    }
    .stat {
      text-align: center;
    }
    .stat-value {
      font-size: 24px;
      font-weight: bold;
    }
    .stat-label {
      font-size: 12px;
      color: #666;
      text-transform: uppercase;
    }
    .stat-value.passed { color: #48bb78; }
    .stat-value.failed { color: #f56565; }
    .stat-value.pending { color: #ed8936; }
    .tests {
      padding: 30px;
    }
    .test-item {
      border: 1px solid #e0e0e0;
      border-radius: 8px;
      margin-bottom: 15px;
      overflow: hidden;
      transition: all 0.3s;
    }
    .test-item:hover {
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    }
    .test-header {
      padding: 20px;
      background: white;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 15px;
    }
    .test-status {
      width: 40px;
      height: 40px;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
      flex-shrink: 0;
    }
    .test-status.pending { background: #e0e0e0; color: #666; }
    .test-status.running { background: #ffd93d; color: #856404; animation: pulse 1s infinite; }
    .test-status.passed { background: #d4edda; color: #155724; }
    .test-status.failed { background: #f8d7da; color: #721c24; }
    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.7; }
    }
    .test-info {
      flex: 1;
    }
    .test-name {
      font-size: 16px;
      font-weight: 600;
      margin-bottom: 5px;
      color: #333;
    }
    .test-description {
      font-size: 14px;
      color: #666;
    }
    .test-meta {
      display: flex;
      gap: 15px;
      font-size: 12px;
      color: #999;
      margin-top: 5px;
    }
    .test-actions {
      display: flex;
      gap: 10px;
    }
    .btn-small {
      padding: 6px 12px;
      font-size: 12px;
    }
    .test-details {
      max-height: 0;
      overflow: hidden;
      transition: max-height 0.3s ease;
    }
    .test-details.expanded {
      max-height: 2000px;
    }
    .test-content {
      padding: 20px;
      background: #f8f9fa;
      border-top: 1px solid #e0e0e0;
    }
    .detail-section {
      margin-bottom: 20px;
    }
    .detail-section:last-child {
      margin-bottom: 0;
    }
    .detail-title {
      font-weight: 600;
      font-size: 14px;
      color: #333;
      margin-bottom: 10px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .code-block {
      background: #2d3748;
      color: #e2e8f0;
      padding: 15px;
      border-radius: 6px;
      overflow-x: auto;
      font-family: 'Courier New', monospace;
      font-size: 13px;
      line-height: 1.5;
    }
    .diff {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 15px;
    }
    .diff-panel {
      background: #2d3748;
      padding: 15px;
      border-radius: 6px;
    }
    .diff-title {
      color: #a0aec0;
      font-size: 12px;
      margin-bottom: 10px;
      text-transform: uppercase;
    }
    .diff-content {
      color: #e2e8f0;
      font-family: 'Courier New', monospace;
      font-size: 13px;
      white-space: pre-wrap;
    }
    .highlight-pass {
      background: rgba(72, 187, 120, 0.2);
      padding: 2px 4px;
      border-radius: 3px;
    }
    .highlight-fail {
      background: rgba(245, 101, 101, 0.2);
      padding: 2px 4px;
      border-radius: 3px;
    }
    .loading {
      text-align: center;
      padding: 40px;
      color: #666;
    }
    .spinner {
      border: 3px solid #f3f3f3;
      border-top: 3px solid #667eea;
      border-radius: 50%;
      width: 40px;
      height: 40px;
      animation: spin 1s linear infinite;
      margin: 0 auto 15px;
    }
    @keyframes spin {
      0% { transform: rotate(0deg); }
      100% { transform: rotate(360deg); }
    }
    .filter-bar {
      display: flex;
      gap: 10px;
      margin-bottom: 20px;
    }
    .filter-btn {
      padding: 8px 16px;
      border: 1px solid #e0e0e0;
      background: white;
      border-radius: 6px;
      cursor: pointer;
      font-size: 13px;
      transition: all 0.2s;
    }
    .filter-btn.active {
      background: #667eea;
      color: white;
      border-color: #667eea;
    }
    .filter-btn:hover {
      border-color: #667eea;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🧪 Translation API Test Runner</h1>
      <p>Visual test suite for the Translation API with dev mode authentication bypass</p>
    </div>

    <div class="controls">
      <button class="btn btn-primary" onclick="runAllTests()">▶ Run All Tests</button>
      <button class="btn btn-secondary" onclick="runSelectedTests()">▶ Run Selected</button>
      <button class="btn btn-danger" onclick="clearResults()">✕ Clear Results</button>

      <div class="stats">
        <div class="stat">
          <div class="stat-value passed" id="passed-count">0</div>
          <div class="stat-label">Passed</div>
        </div>
        <div class="stat">
          <div class="stat-value failed" id="failed-count">0</div>
          <div class="stat-label">Failed</div>
        </div>
        <div class="stat">
          <div class="stat-value pending" id="pending-count">0</div>
          <div class="stat-label">Total</div>
        </div>
      </div>
    </div>

    <div class="tests">
      <div class="filter-bar">
        <button class="filter-btn active" onclick="filterTests('all')">All Tests</button>
        <button class="filter-btn" onclick="filterTests('passed')">Passed</button>
        <button class="filter-btn" onclick="filterTests('failed')">Failed</button>
        <button class="filter-btn" onclick="filterTests('pending')">Not Run</button>
      </div>

      <div id="test-list" class="loading">
        <div class="spinner"></div>
        <p>Loading tests...</p>
      </div>
    </div>
  </div>

  <script>
    let tests = [];
    let results = {};
    let selectedTests = new Set();
    let currentFilter = 'all';

    // Load tests on page load
    async function loadTests() {
      try {
        const response = await fetch('/api/tests');
        tests = await response.json();
        renderTests();
        updateStats();
      } catch (error) {
        document.getElementById('test-list').innerHTML =
          '<p style="color: #f56565;">Error loading tests: ' + error.message + '</p>';
      }
    }

    // Render test list
    function renderTests() {
      const container = document.getElementById('test-list');

      const filteredTests = tests.filter(test => {
        if (currentFilter === 'all') return true;
        const result = results[test.id];
        if (currentFilter === 'pending') return !result;
        if (currentFilter === 'passed') return result && result.passed;
        if (currentFilter === 'failed') return result && !result.passed;
        return true;
      });

      container.innerHTML = filteredTests.map(test => {
        const result = results[test.id];
        const status = result ? (result.passed ? 'passed' : 'failed') : 'pending';
        const statusIcon = status === 'passed' ? '✓' : status === 'failed' ? '✗' : '○';
        const isSelected = selectedTests.has(test.id);

        return \`
          <div class="test-item" data-test-id="\${test.id}" data-status="\${status}">
            <div class="test-header" onclick="toggleTest('\${test.id}')">
              <div class="test-status \${status}">\${statusIcon}</div>
              <div class="test-info">
                <div class="test-name">\${test.description || test.id}</div>
                <div class="test-description">\${test.notes || ''}</div>
                <div class="test-meta">
                  <span>ID: \${test.id}</span>
                  \${result ? \`<span>Response: \${result.responseTime}ms</span>\` : ''}
                  \${result && result.statusCode ? \`<span>Status: \${result.statusCode}</span>\` : ''}
                </div>
              </div>
              <div class="test-actions" onclick="event.stopPropagation()">
                <label style="display: flex; align-items: center; gap: 5px; cursor: pointer;">
                  <input type="checkbox" \${isSelected ? 'checked' : ''}
                         onchange="toggleSelection('\${test.id}')">
                  <span style="font-size: 12px;">Select</span>
                </label>
                <button class="btn btn-primary btn-small" onclick="runSingleTest('\${test.id}')">
                  Run
                </button>
              </div>
            </div>
            <div class="test-details" id="details-\${test.id}">
              <div class="test-content" id="content-\${test.id}">
                <!-- Details loaded dynamically -->
              </div>
            </div>
          </div>
        \`;
      }).join('');
    }

    // Render test details
    function renderTestDetails(test, result) {
      let html = \`
        <div class="detail-section">
          <div class="detail-title">Request</div>
          <div class="code-block">\${JSON.stringify(test.request, null, 2)}</div>
        </div>
      \`;

      if (result) {
        if (result.error) {
          html += \`
            <div class="detail-section">
              <div class="detail-title">Error</div>
              <div class="code-block" style="color: #fc8181;">\${result.error}</div>
            </div>
          \`;
        } else {
          html += \`
            <div class="detail-section">
              <div class="detail-title">Comparison</div>
              <div class="diff">
                <div class="diff-panel">
                  <div class="diff-title">Expected</div>
                  <div class="diff-content">\${JSON.stringify(test.expected, null, 2)}</div>
                </div>
                <div class="diff-panel">
                  <div class="diff-title">Actual Response</div>
                  <div class="diff-content">\${JSON.stringify(result.response, null, 2)}</div>
                </div>
              </div>
            </div>
          \`;
        }
      }

      return html;
    }

    // Toggle test details
    function toggleTest(testId) {
      const details = document.getElementById('details-' + testId);
      const content = document.getElementById('content-' + testId);

      if (!details.classList.contains('expanded')) {
        // Load details when expanding
        const test = tests.find(t => t.id === testId);
        const result = results[testId];
        content.innerHTML = renderTestDetails(test, result);
      }

      details.classList.toggle('expanded');
    }

    // Toggle test selection
    function toggleSelection(testId) {
      if (selectedTests.has(testId)) {
        selectedTests.delete(testId);
      } else {
        selectedTests.add(testId);
      }
    }

    // Run single test
    async function runSingleTest(testId) {
      const testElement = document.querySelector(\`[data-test-id="\${testId}"]\`);
      const statusElement = testElement.querySelector('.test-status');

      statusElement.className = 'test-status running';
      statusElement.textContent = '⟳';

      try {
        const response = await fetch(\`/api/run/\${testId}\`, { method: 'POST' });
        const result = await response.json();

        results[testId] = result;
        renderTests();
        updateStats();
      } catch (error) {
        console.error('Test failed:', error);
        results[testId] = { passed: false, error: error.message };
        renderTests();
        updateStats();
      }
    }

    // Run all tests
    async function runAllTests() {
      for (const test of tests) {
        await runSingleTest(test.id);
        await new Promise(resolve => setTimeout(resolve, 100)); // Small delay between tests
      }
    }

    // Run selected tests
    async function runSelectedTests() {
      if (selectedTests.size === 0) {
        alert('Please select at least one test');
        return;
      }

      for (const testId of selectedTests) {
        await runSingleTest(testId);
        await new Promise(resolve => setTimeout(resolve, 100));
      }
    }

    // Clear results
    function clearResults() {
      results = {};
      selectedTests.clear();
      renderTests();
      updateStats();
    }

    // Update statistics
    function updateStats() {
      const passed = Object.values(results).filter(r => r.passed).length;
      const failed = Object.values(results).filter(r => !r.passed).length;

      document.getElementById('passed-count').textContent = passed;
      document.getElementById('failed-count').textContent = failed;
      document.getElementById('pending-count').textContent = tests.length;
    }

    // Filter tests
    function filterTests(filter) {
      currentFilter = filter;
      document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.classList.remove('active');
      });
      event.target.classList.add('active');
      renderTests();
    }

    // Initialize
    loadTests();
  </script>
</body>
</html>`;
}

server.listen(PORT, () => {
  console.log(`
╔════════════════════════════════════════════════════════╗
║   Translation API Test Runner                          ║
║                                                         ║
║   🌐 Server running at: http://localhost:${PORT}        ║
║   📝 Test file: translation_test_cases.json            ║
║   📊 Total tests: ${testCases.length}                                     ║
║                                                         ║
║   Open your browser and start testing!                 ║
╚════════════════════════════════════════════════════════╝
  `);
});
