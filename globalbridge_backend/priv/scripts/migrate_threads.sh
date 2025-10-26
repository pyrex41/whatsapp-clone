#!/bin/bash
# Script to add translation columns to all thread databases

set -e

echo "=== Thread Database Migration ==="
echo "Adding translation columns to messages table..."
echo

SUCCESS=0
ALREADY_MIGRATED=0
FAILED=0

for db in priv/threads/*.db; do
  if [ -f "$db" ]; then
    echo "Processing: $db"

    # Check if columns already exist
    EXISTING=$(sqlite3 "$db" "PRAGMA table_info(messages);" | grep -c "original_content\|translated_content\|source_language\|target_language\|is_translated" || true)

    if [ "$EXISTING" -eq 5 ]; then
      echo "  ✅ Already has all translation columns"
      ((ALREADY_MIGRATED++))
    else
      # Add columns (ignore errors if column already exists)
      sqlite3 "$db" "ALTER TABLE messages ADD COLUMN original_content TEXT;" 2>/dev/null || true
      sqlite3 "$db" "ALTER TABLE messages ADD COLUMN translated_content TEXT;" 2>/dev/null || true
      sqlite3 "$db" "ALTER TABLE messages ADD COLUMN source_language TEXT;" 2>/dev/null || true
      sqlite3 "$db" "ALTER TABLE messages ADD COLUMN target_language TEXT;" 2>/dev/null || true
      sqlite3 "$db" "ALTER TABLE messages ADD COLUMN is_translated INTEGER DEFAULT 0;" 2>/dev/null || true

      # Verify columns were added
      NEW_COUNT=$(sqlite3 "$db" "PRAGMA table_info(messages);" | grep -c "original_content\|translated_content\|source_language\|target_language\|is_translated" || true)

      if [ "$NEW_COUNT" -eq 5 ]; then
        echo "  ✅ Successfully migrated"
        ((SUCCESS++))
      else
        echo "  ❌ Migration failed (only $NEW_COUNT/5 columns added)"
        ((FAILED++))
      fi
    fi
  fi
done

echo
echo "=== Migration Summary ==="
echo "Successfully migrated: $SUCCESS"
echo "Already migrated: $ALREADY_MIGRATED"
echo "Failed: $FAILED"
echo "Total: $((SUCCESS + ALREADY_MIGRATED + FAILED))"
