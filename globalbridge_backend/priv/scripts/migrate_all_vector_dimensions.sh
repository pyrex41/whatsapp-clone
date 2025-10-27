#!/bin/bash
# Migrate ALL vector tables from 3072 to 1536 dimensions
# Run with: bash priv/scripts/migrate_all_vector_dimensions.sh

echo "🔧 Starting vector dimension migration for all thread databases..."
echo ""

# Find all thread database files
SHARD_DIR="priv/threads"
SHARD_FILES=$(find $SHARD_DIR -name "*.db" 2>/dev/null)

if [ -z "$SHARD_FILES" ]; then
    echo "⚠️  No thread databases found in $SHARD_DIR"
    exit 1
fi

TOTAL_DBS=$(echo "$SHARD_FILES" | wc -l | tr -d ' ')
echo "📊 Found $TOTAL_DBS thread databases"
echo ""

CURRENT=0

# Process each shard
for shard_file in $SHARD_FILES; do
    CURRENT=$((CURRENT + 1))
    BASENAME=$(basename "$shard_file")

    echo "[$CURRENT/$TOTAL_DBS] 🔨 Migrating $BASENAME..."

    # Drop all three vector tables
    sqlite3 "$shard_file" "DROP TABLE IF EXISTS message_embeddings;" 2>&1 | grep -v "no such module" > /dev/null
    sqlite3 "$shard_file" "DROP TABLE IF EXISTS user_style_embeddings;" 2>&1 | grep -v "no such module" > /dev/null
    sqlite3 "$shard_file" "DROP TABLE IF EXISTS feedback_embeddings;" 2>&1 | grep -v "no such module" > /dev/null

    echo "  ✅ Dropped old vector tables (3072 dimensions)"
    echo "  ℹ️  Tables will be recreated with 1536 dimensions on next access"
done

echo ""
echo "✅ Vector dimension migration complete!"
echo ""
echo "📝 Summary:"
echo "   - Processed: $TOTAL_DBS databases"
echo "   - Dropped: message_embeddings, user_style_embeddings, feedback_embeddings"
echo "   - New dimension: 1536 (will be recreated automatically)"
echo ""
echo "🚀 Next: Restart your backend application"
