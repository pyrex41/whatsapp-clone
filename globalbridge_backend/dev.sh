#!/bin/bash
# Load environment variables from .env file and start Phoenix server

# Check for force flag
FORCE=false
for arg in "$@"; do
    case $arg in
        -f|--force)
            FORCE=true
            shift
            ;;
    esac
done

if [ "$FORCE" = true ]; then
    echo "🔨 Force mode: Killing any processes on port 4000..."
    lsof -ti:4000 | xargs kill -9 2>/dev/null || echo "No processes found on port 4000"
fi

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    echo "Please create a .env file with your Auth0 credentials."
    exit 1
fi

# Load environment variables
echo "🔧 Loading environment variables from .env..."
export $(grep -v '^#' .env | xargs)

# sqlite-vec: auto-detect local path or disable if missing (prevents boot failures)
detect_vec() {
  # If explicitly set but missing, warn and unset to avoid crashing in dev
  if [ -n "$SQLITE_VEC_PATH" ] && [ ! -f "$SQLITE_VEC_PATH" ]; then
    echo "⚠️  SQLITE_VEC_PATH set but file not found: $SQLITE_VEC_PATH — unsetting for dev"
    unset SQLITE_VEC_PATH
  fi

  # If not set, try common locations
  if [ -z "$SQLITE_VEC_PATH" ]; then
    CANDIDATES=(
      "/opt/homebrew/lib/vec0.dylib"    # macOS Apple Silicon
      "/usr/local/lib/vec0.dylib"       # macOS Intel/Homebrew
      "/opt/me/lib/vec0.dylib"          # custom local macOS install
      "/usr/local/lib/vec0.so"          # Linux
      "/usr/lib/x86_64-linux-gnu/vec0.so"
    )
    for p in "${CANDIDATES[@]}"; do
      if [ -f "$p" ]; then
        export SQLITE_VEC_PATH="$p"
        echo "✅ sqlite-vec detected at $SQLITE_VEC_PATH"
        return
      fi
    done
    echo "ℹ️  sqlite-vec not found locally; vector features disabled in dev"
  fi
}

detect_vec

# Verify Auth0 variables are set
if [ -z "$AUTH0_DOMAIN" ]; then
    echo "❌ AUTH0_DOMAIN not set in .env"
    exit 1
fi

if [ -z "$AUTH0_CLIENT_ID" ]; then
    echo "❌ AUTH0_CLIENT_ID not set in .env"
    exit 1
fi

echo "✅ Auth0 configuration loaded:"
echo "   Domain: $AUTH0_DOMAIN"
echo "   Client ID: $AUTH0_CLIENT_ID"
echo "   Audience: $AUTH0_AUDIENCE"
echo ""

# Start Phoenix server
echo "🚀 Starting Phoenix server..."
mix phx.server
