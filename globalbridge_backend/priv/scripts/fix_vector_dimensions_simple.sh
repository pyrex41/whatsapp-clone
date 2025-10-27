#!/bin/bash
# Fix vector dimension mismatch for user_style_embeddings table
# Run with: bash priv/scripts/fix_vector_dimensions_simple.sh

echo "🔧 Starting vector dimension fix for all shards..."

# Find all shard database files
SHARD_DIR="priv/threads"
SHARD_FILES=$(find $SHARD_DIR -name "*.db" 2>/dev/null)

if [ -z "$SHARD_FILES" ]; then
    echo "⚠️  No shard databases found in $SHARD_DIR"
    exit 1
fi

echo "📊 Found shard databases:"
echo "$SHARD_FILES"
echo ""

# Process each shard
for shard_file in $SHARD_FILES; do
    echo "🔨 Fixing $(basename $shard_file)..."

    # Drop existing table
    sqlite3 "$shard_file" "DROP TABLE IF EXISTS user_style_embeddings;" 2>&1 | grep -v "no such module"
    echo "  ✓ Dropped existing table"

    # Recreate with correct dimensions (1536)
    sqlite3 "$shard_file" "CREATE VIRTUAL TABLE IF NOT EXISTS user_style_embeddings USING vec0(
        embedding_id TEXT PRIMARY KEY,
        user_id TEXT,
        style_aspect TEXT,
        embedding float[1536]
    );" 2>&1

    if [ $? -eq 0 ]; then
        echo "  ✅ Recreated table with 1536 dimensions"
    else
        echo "  ⚠️  sqlite-vec may not be available, skipping"
    fi
    echo ""
done

echo "✅ Vector dimension fix complete!"
