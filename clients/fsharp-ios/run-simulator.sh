#!/bin/bash
# Script to run GlobalBridge F# iOS app in simulator with environment variables

set -e

# Load environment variables from .env if it exists (robustly)
if [ -f .env ]; then
    echo "Loading environment variables from .env..."
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
else
    echo "Warning: .env file not found. Using default values."
    echo "Copy .env.example to .env and configure your values."
fi

# Default values if not set
export AUTH0_DOMAIN="${AUTH0_DOMAIN:-https://example.auth0.com}"
export AUTH0_CLIENT_ID="${AUTH0_CLIENT_ID:-development-client-id}"
export AUTH0_CALLBACK_SCHEME="${AUTH0_CALLBACK_SCHEME:-globalbridge}"
export BACKEND_BASE_URI="${BACKEND_BASE_URI:-https://api.globalbridge.dev}"
export PHOENIX_ENDPOINT="${PHOENIX_ENDPOINT:-wss://api.globalbridge.dev/socket}"

echo "Building with environment variables:"
echo "  AUTH0_DOMAIN: $AUTH0_DOMAIN"
echo "  AUTH0_CLIENT_ID: $AUTH0_CLIENT_ID"
echo "  AUTH0_CALLBACK_SCHEME: $AUTH0_CALLBACK_SCHEME"
echo "  BACKEND_BASE_URI: $BACKEND_BASE_URI"
echo "  PHOENIX_ENDPOINT: $PHOENIX_ENDPOINT"
echo ""

# Build the app
echo "Building iOS app..."
dotnet build src/GlobalBridge.iOS/GlobalBridge.iOS.fsproj \
  -c Debug \
  -t:Build \
  /p:RuntimeIdentifier=iossimulator-arm64 \
  /p:Platform=iPhoneSimulator \
  /p:Configuration=Debug

open -a Simulator || true

# Pick a reasonable default simulator (prefer iPhone 17/16/15 Pro, else any iPhone)
echo "Checking simulator status..."
SIMULATOR_ID=$(xcrun simctl list devices available | awk '/iPhone 17 Pro \(/ {print $0}' | head -1 | sed -n 's/.*(\([0-9A-F-]*\)).*/\1/p')
if [ -z "$SIMULATOR_ID" ]; then
  SIMULATOR_ID=$(xcrun simctl list devices available | awk '/iPhone 16 Pro \(/ {print $0}' | head -1 | sed -n 's/.*(\([0-9A-F-]*\)).*/\1/p')
fi
if [ -z "$SIMULATOR_ID" ]; then
  SIMULATOR_ID=$(xcrun simctl list devices available | awk '/iPhone 15 Pro \(/ {print $0}' | head -1 | sed -n 's/.*(\([0-9A-F-]*\)).*/\1/p')
fi
if [ -z "$SIMULATOR_ID" ]; then
  SIMULATOR_ID=$(xcrun simctl list devices available | awk '/iPhone \(/ {print $0}' | head -1 | sed -n 's/.*(\([0-9A-F-]*\)).*/\1/p')
fi

if [ -z "$SIMULATOR_ID" ]; then
  echo "Error: No available iPhone simulators found"
  xcrun simctl list devices
  exit 1
fi

if ! xcrun simctl list devices | grep "$SIMULATOR_ID" | grep -q Booted; then
  echo "Booting simulator $SIMULATOR_ID..."
  xcrun simctl boot "$SIMULATOR_ID" || true
  sleep 5
fi

# Install the app
echo "Installing app to simulator..."
xcrun simctl install "$SIMULATOR_ID" \
  src/GlobalBridge.iOS/bin/Debug/net9.0-ios18.0/iossimulator-arm64/GlobalBridge.iOS.app

# Launch with environment variables (inject into Simulator process env)
echo "Launching app with environment variables..."
for key in AUTH0_DOMAIN AUTH0_CLIENT_ID AUTH0_AUDIENCE AUTH0_CALLBACK_SCHEME BACKEND_BASE_URI PHOENIX_ENDPOINT; do
  val=$(printenv "$key" || true)
  if [ -n "$val" ]; then
    xcrun simctl spawn "$SIMULATOR_ID" launchctl setenv "$key" "$val" || true
  fi
done
xcrun simctl launch --console-pty "$SIMULATOR_ID" com.globalbridge.mobile.fs || true

echo ""
echo "✅ App launched successfully!"
echo "To view logs, run:"
echo "  xcrun simctl spawn $SIMULATOR_ID log stream --predicate 'processImagePath contains \"GlobalBridge\"'"
