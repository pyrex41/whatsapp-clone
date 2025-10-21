#!/bin/bash

# Start the Phoenix backend server for GlobalBridge

echo "🚀 Starting GlobalBridge Backend..."

cd globalbridge_backend

# Check if dependencies are installed
if [ ! -d "deps" ]; then
    echo "📦 Installing dependencies..."
    mix deps.get
fi

# Check if database exists
if [ ! -f "priv/shared_dbs/users.db" ]; then
    echo "🗄️ Creating database..."
    mix ecto.create
fi

# Run migrations
echo "📊 Running database migrations..."
mix ecto.migrate

# Start the server
echo "🌐 Starting Phoenix server on http://localhost:4000"
echo "📱 WebSocket endpoint: ws://localhost:4000/socket"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

# Start Phoenix server
mix phx.server
