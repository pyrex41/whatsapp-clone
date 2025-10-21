import * as SQLite from 'expo-sqlite';

import type { ApiCDCEntry, ApiMessage, ApiThread } from '~/api/schemas';

const DATABASE_NAME = 'globalbridge_cdc.db';

type SQLiteDatabase = SQLite.SQLiteDatabase;

let databasePromise: Promise<SQLiteDatabase> | null = null;

async function getDatabase(): Promise<SQLiteDatabase> {
  if (!databasePromise) {
    databasePromise = (async () => {
      const db = await SQLite.openDatabaseAsync(DATABASE_NAME);
      await db.execAsync(`
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS threads (
          id TEXT PRIMARY KEY,
          data TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS messages (
          id TEXT PRIMARY KEY,
          thread_id TEXT NOT NULL,
          data TEXT NOT NULL,
          inserted_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_messages_thread ON messages(thread_id, inserted_at DESC);
        CREATE TABLE IF NOT EXISTS cdc_state (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      `);
      return db;
    })();
  }
  return databasePromise;
}

function safeParse<T>(value: string): T | null {
  try {
    return JSON.parse(value) as T;
  } catch (error) {
    console.warn('[cdc-database] Failed to parse JSON payload', error);
    return null;
  }
}

export async function fetchCachedThreads(): Promise<ApiThread[]> {
  const db = await getDatabase();
  const rows = await db.getAllAsync<{ data: string }>(
    'SELECT data FROM threads ORDER BY updated_at DESC',
  );
  return rows
    .map((row) => safeParse<ApiThread>(row.data))
    .filter((thread): thread is ApiThread => Boolean(thread));
}

export async function upsertThreads(threads: ApiThread[]) {
  if (threads.length === 0) return;
  const db = await getDatabase();
  await db.withTransactionAsync(async () => {
    for (const thread of threads) {
      await db.runAsync(
        `INSERT INTO threads (id, data, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
        thread.id,
        JSON.stringify(thread),
        thread.lastMessageAt,
      );
    }
  });
}

export async function removeThreads(threadIds: string[]) {
  if (threadIds.length === 0) return;
  const db = await getDatabase();
  const placeholders = threadIds.map(() => '?').join(',');
  await db.runAsync(`DELETE FROM threads WHERE id IN (${placeholders})`, threadIds);
}

export interface CachedMessagesParams {
  threadId: string;
  limit?: number;
  before?: string;
}

export async function fetchCachedMessages({
  threadId,
  limit = 50,
  before,
}: CachedMessagesParams): Promise<ApiMessage[]> {
  const db = await getDatabase();
  const rows = await db.getAllAsync<{ data: string }>(
    `SELECT data FROM messages
     WHERE thread_id = ?
     ${before ? 'AND inserted_at < ?' : ''}
     ORDER BY inserted_at DESC
     LIMIT ?`,
    before ? [threadId, before, limit] : [threadId, limit],
  );
  return rows
    .map((row) => safeParse<ApiMessage>(row.data))
    .filter((message): message is ApiMessage => Boolean(message));
}

export async function upsertMessages(messages: ApiMessage[]) {
  if (messages.length === 0) return;
  const db = await getDatabase();
  await db.withTransactionAsync(async () => {
    for (const message of messages) {
      await db.runAsync(
        `INSERT INTO messages (id, thread_id, data, inserted_at, updated_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE
         SET data = excluded.data,
             thread_id = excluded.thread_id,
             inserted_at = excluded.inserted_at,
             updated_at = excluded.updated_at`,
        message.id,
        message.threadId,
        JSON.stringify(message),
        message.insertedAt,
        message.updatedAt,
      );
    }
  });
}

export async function deleteMessage(messageId: string) {
  const db = await getDatabase();
  await db.runAsync('DELETE FROM messages WHERE id = ?', messageId);
}

export async function readCdcCursor(threadId: string): Promise<number | string | null> {
  const db = await getDatabase();
  const row = await db.getFirstAsync<{ value: string }>('SELECT value FROM cdc_state WHERE key = ?', `thread:${threadId}:cursor`);
  if (!row) return null;
  const value = row.value;
  const numeric = Number(value);
  return Number.isNaN(numeric) ? value : numeric;
}

export async function writeCdcCursor(threadId: string, cursor: number | string | null) {
  const db = await getDatabase();
  if (cursor === null || cursor === undefined) {
    await db.runAsync('DELETE FROM cdc_state WHERE key = ?', `thread:${threadId}:cursor`);
    return;
  }
  await db.runAsync(
    `INSERT INTO cdc_state (key, value)
     VALUES (?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
    `thread:${threadId}:cursor`,
    String(cursor),
  );
}

function asApiThread(data: unknown): ApiThread | null {
  if (!data || typeof data !== 'object') return null;
  try {
    const serialized = JSON.stringify(data);
    return JSON.parse(serialized) as ApiThread;
  } catch (error) {
    console.warn('[cdc-database] Failed to coerce CDC thread payload', error);
    return null;
  }
}

function asApiMessage(data: unknown): ApiMessage | null {
  if (!data || typeof data !== 'object') return null;
  try {
    const serialized = JSON.stringify(data);
    return JSON.parse(serialized) as ApiMessage;
  } catch (error) {
    console.warn('[cdc-database] Failed to coerce CDC message payload', error);
    return null;
  }
}

export async function applyCdcChanges(threadId: string, changes: ApiCDCEntry[]) {
  if (changes.length === 0) return;
  const db = await getDatabase();
  await db.withTransactionAsync(async () => {
    for (const change of changes) {
      if (change.tableName === 'threads') {
        const thread = asApiThread(change.newData ?? change.oldData);
        if (!thread) continue;
        if (change.operation === 'DELETE') {
          await db.runAsync('DELETE FROM threads WHERE id = ?', thread.id);
        } else {
          await db.runAsync(
            `INSERT INTO threads (id, data, updated_at)
             VALUES (?, ?, ?)
             ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
            thread.id,
            JSON.stringify(thread),
            thread.lastMessageAt,
          );
        }
        continue;
      }

      if (change.tableName === 'messages') {
        if (change.operation === 'DELETE') {
          await db.runAsync('DELETE FROM messages WHERE id = ?', change.recordId);
        } else {
          const message = asApiMessage(change.newData ?? change.oldData);
          if (!message) continue;
          await db.runAsync(
            `INSERT INTO messages (id, thread_id, data, inserted_at, updated_at)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(id) DO UPDATE
             SET data = excluded.data,
                 thread_id = excluded.thread_id,
                 inserted_at = excluded.inserted_at,
                 updated_at = excluded.updated_at`,
            message.id,
            message.threadId,
            JSON.stringify(message),
            message.insertedAt,
            message.updatedAt,
          );
        }
      }
    }
  });
}
