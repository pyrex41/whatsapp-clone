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

# Optional: Set SQLITE_VEC_PATH if you have the sqlite-vec extension installed
# Uncomment and set the path to your vec0 shared library (e.g., libvec0.dylib on macOS, libvec0.so on Linux)
# export SQLITE_VEC_PATH="/path/to/vec0.dylib"
# Or if installed via Homebrew on macOS:
# export SQLITE_VEC_PATH="$(brew --prefix)/lib/vec0.dylib"

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
