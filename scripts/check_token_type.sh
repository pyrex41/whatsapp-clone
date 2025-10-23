#!/bin/bash

# Token Type Checker - Determines if token is JWT or JWE
# Usage: ./check_token_type.sh "your_token_here"

set -e

TOKEN="$1"

if [ -z "$TOKEN" ]; then
    echo ""
    echo "❌ No token provided"
    echo ""
    echo "Usage: $0 <token>"
    echo ""
    echo "Example:"
    echo "  $0 \"eyJhbGci...\""
    echo ""
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 TOKEN TYPE ANALYZER"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Count parts (split by .)
PARTS=$(echo "$TOKEN" | tr '.' '\n' | wc -l | xargs)

echo "📊 Token Structure:"
echo "   Parts: $PARTS"
echo ""

if [ "$PARTS" -eq 3 ]; then
    echo "✅ Type: JWT (JSON Web Token)"
    echo "   Format: header.payload.signature"
    echo ""

    # Decode header
    HEADER=$(echo "$TOKEN" | cut -d'.' -f1)
    echo "📋 Header (decoded):"
    # Try decoding with padding
    HEADER_PADDED="${HEADER}=="
    HEADER_JSON=$(echo "$HEADER_PADDED" | base64 -d 2>/dev/null || echo "")

    if [ -n "$HEADER_JSON" ]; then
        if command -v jq &> /dev/null; then
            echo "$HEADER_JSON" | jq '.' 2>/dev/null || echo "$HEADER_JSON"
        else
            echo "$HEADER_JSON"
        fi
    else
        echo "   (Failed to decode header)"
    fi
    echo ""

    # Try to decode payload
    PAYLOAD=$(echo "$TOKEN" | cut -d'.' -f2)
    echo "📦 Payload (decoded - first 500 chars):"
    PAYLOAD_PADDED="${PAYLOAD}=="
    PAYLOAD_JSON=$(echo "$PAYLOAD_PADDED" | base64 -d 2>/dev/null || echo "")

    if [ -n "$PAYLOAD_JSON" ]; then
        if command -v jq &> /dev/null; then
            echo "$PAYLOAD_JSON" | jq '.' 2>/dev/null | head -c 500 || echo "$PAYLOAD_JSON" | head -c 500
        else
            echo "$PAYLOAD_JSON" | head -c 500
        fi
    else
        echo "   (Failed to decode payload)"
    fi
    echo ""
    echo "✅ Backend can decode this token (after signature verification)"

elif [ "$PARTS" -eq 5 ] || [ "$PARTS" -eq 4 ]; then
    echo "❌ Type: JWE (JSON Web Encryption)"
    echo "   Format: header.encrypted_key.iv.ciphertext.auth_tag"
    echo ""

    # Decode header (only readable part)
    HEADER=$(echo "$TOKEN" | cut -d'.' -f1)
    echo "📋 Header (decoded):"
    HEADER_PADDED="${HEADER}=="
    HEADER_JSON=$(echo "$HEADER_PADDED" | base64 -d 2>/dev/null || echo "")

    if [ -n "$HEADER_JSON" ]; then
        if command -v jq &> /dev/null; then
            echo "$HEADER_JSON" | jq '.' 2>/dev/null || echo "$HEADER_JSON"
        else
            echo "$HEADER_JSON"
        fi

        # Extract encryption details
        if command -v jq &> /dev/null; then
            ALG=$(echo "$HEADER_JSON" | jq -r '.alg' 2>/dev/null)
            ENC=$(echo "$HEADER_JSON" | jq -r '.enc' 2>/dev/null)
            echo ""
            echo "🔐 Encryption Details:"
            echo "   Algorithm: $ALG"
            echo "   Encryption: $ENC"
        fi
    else
        echo "   (Failed to decode header)"
    fi
    echo ""
    echo "📦 Payload:"
    echo "   ⚠️  ENCRYPTED - Cannot decode without decryption key!"
    echo ""
    echo "❌ Backend CANNOT decode this token - it's encrypted!"
    echo ""
    echo "🔧 FIX REQUIRED:"
    echo "   1. Go to Auth0 Dashboard"
    echo "   2. Applications → Settings → Advanced Settings"
    echo "   3. Find 'ID Token Encryption'"
    echo "   4. DISABLE encryption"
    echo "   5. Save and re-login in iOS app"

else
    echo "⚠️  Type: Unknown ($PARTS parts)"
    echo "   Expected: 3 (JWT) or 5 (JWE)"
    echo ""
    echo "   This might be a malformed token."
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Summary
if [ "$PARTS" -eq 3 ]; then
    exit 0  # Success - JWT
else
    exit 1  # Failure - JWE or unknown
fi
