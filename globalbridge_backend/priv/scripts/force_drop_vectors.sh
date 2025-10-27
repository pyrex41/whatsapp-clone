#!/bin/bash
# Force drop vector tables with proper error handling
# Run with: bash priv/scripts/force_drop_vectors.sh

echo "🔧 Force dropping all vector tables..."
echo ""

SHARD_DIR="priv/threads"
TOTAL=0
SUCCESS=0
FAILED=0

for shard_file in $(find $SHARD_DIR -name "*.db" 2>/dev/null); do
    TOTAL=$((TOTAL + 1))
    BASENAME=$(basename "$shard_file")

    # Try to drop each table
    if sqlite3 "$shard_file" "DROP TABLE message_embeddings; DROP TABLE user_style_embeddings; DROP TABLE feedback_embeddings;" 2>/dev/null; then
        SUCCESS=$((SUCCESS + 1))
        echo "✅ [$TOTAL] $BASENAME"
    else
        FAILED=$((FAILED + 1))
        echo "⚠️  [$TOTAL] $BASENAME (some tables may not exist)"
    fi
done

echo ""
echo "📊 Summary:"
echo "   Total: $TOTAL databases"
echo "   Success: $SUCCESS"
echo "   Warnings: $FAILED"
