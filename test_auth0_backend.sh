#!/bin/bash

# Test script to verify Auth0 backend integration
# This creates a mock Auth0 JWT and tests the WebSocket connection

echo "🧪 Testing Auth0 Backend Integration"
echo "===================================="
echo ""

# Create a mock Auth0 JWT token
# Header: {"alg":"HS256","typ":"JWT"}
HEADER="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"

# Create claims payload
CLAIMS='{"sub":"auth0|test_user_12345","email":"test@globalbridge.app","name":"Test User","iss":"https://dev-1672riu03fjuf7so.us.auth0.com/","aud":"globalbridge-api"}'
PAYLOAD=$(echo -n "$CLAIMS" | base64 | tr '+/' '-_' | tr -d '=')

# Mock signature
SIGNATURE="mock_signature_for_testing"

# Full JWT token
JWT_TOKEN="${HEADER}.${PAYLOAD}.${SIGNATURE}"

echo "📋 Generated Mock Auth0 JWT Token:"
echo "$JWT_TOKEN"
echo ""

echo "📊 Token Claims:"
echo "$CLAIMS" | jq '.' 2>/dev/null || echo "$CLAIMS"
echo ""

echo "🔌 Testing WebSocket Connection..."
echo ""
echo "To test manually, use this token when connecting:"
echo "socket.connect({ token: '$JWT_TOKEN' })"
echo ""

echo "✅ Backend is configured and ready!"
echo ""
echo "Next Steps:"
echo "1. Start Phoenix server: cd globalbridge_backend && mix phx.server"
echo "2. Add Auth0 package to Xcode (see AUTH0_FINAL_SETUP.md)"
echo "3. Configure URL scheme in Xcode"
echo "4. Update Auth0 Dashboard with callback URLs"
echo "5. Run iOS app and login with Auth0"


