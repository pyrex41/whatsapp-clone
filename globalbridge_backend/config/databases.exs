import Config

# Database Architecture Configuration
# This file documents the multi-database setup for GlobalBridge

# Primary Repo (users.db) - configured in dev.exs, test.exs, runtime.exs
# - users
# - sessions
# - devices
# - contacts

# Additional databases (accessed via custom modules):

# BridgeRepo (bridges.db)
# - bridge_sessions
# - bridge_metadata
# - bridge_health_checks

# SyncStateRepo (sync_state.db)
# - device_sync_state
# - message_sync_cursors
# - pending_syncs

# ThreadRepo (threads/thread_{id}.db) - dynamically sharded
# - messages
# - media_attachments
# - read_receipts
# - reactions

# Note: Actual Repo module implementations will be created in lib/globalbridge_backend/
