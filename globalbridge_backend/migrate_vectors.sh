#!/bin/bash
# Run vector dimension migration with environment variables from .env

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found!"
    echo "Please create a .env file with your Auth0 credentials."
    exit 1
fi

# Load environment variables
echo "🔧 Loading environment variables from .env..."
export $(grep -v '^#' .env | xargs)

# Detect sqlite-vec
detect_vec() {
  if [ -n "$SQLITE_VEC_PATH" ] && [ ! -f "$SQLITE_VEC_PATH" ]; then
    echo "⚠️  SQLITE_VEC_PATH set but file not found: $SQLITE_VEC_PATH — unsetting for dev"
    unset SQLITE_VEC_PATH
  fi

  if [ -z "$SQLITE_VEC_PATH" ]; then
    CANDIDATES=(
      "/opt/homebrew/lib/vec0.dylib"
      "/usr/local/lib/vec0.dylib"
      "/opt/me/lib/vec0.dylib"
      "/usr/local/lib/vec0.so"
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

echo "✅ Environment loaded"
echo ""

# Run migration
echo "🔧 Running vector dimension migration..."
mix migrate_vector_dimensions
