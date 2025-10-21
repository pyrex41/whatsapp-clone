import EventEmitter from 'eventemitter3';
import type { Channel, Socket } from 'phoenix';
import { Socket as PhoenixSocket } from 'phoenix';

import { realtimeConfig } from '~/config/realtime';
import type { ApiMessage } from '~/api/schemas';

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'error';

export interface SendMessageOptions {
  content: string;
  contentType?: 'text' | 'image' | 'video' | 'audio' | 'file' | 'location';
  mediaUrl?: string;
  mediaMimeType?: string;
  mediaSize?: number;
  replyToId?: string;
  attachments?: Array<{
    url: string;
    mimeType: string;
    size?: number;
    width?: number;
    height?: number;
    thumbnailUrl?: string | null;
  }>;
}

export interface ThreadTypingState {
  userId: string;
  isTyping: boolean;
  timestamp: number;
}

export interface ThreadPresenceState {
  [userId: string]: {
    onlineAt?: number;
    status?: 'online' | 'offline' | 'away';
    metadata?: Record<string, unknown>;
  };
}

interface ThreadChannelEvents {
  message: (message: ApiMessage) => void;
  message_updated: (message: ApiMessage) => void;
  message_deleted: (messageId: string) => void;
  read_receipt: (payload: { userId: string; messageId: string; readAt: string }) => void;
  typing: (state: ThreadTypingState) => void;
  typing_snapshot: (snapshot: ThreadTypingState[]) => void;
  presence_state: (state: ThreadPresenceState) => void;
  presence_diff: (diff: { joins?: ThreadPresenceState; leaves?: ThreadPresenceState }) => void;
  error: (error: Error) => void;
}

class ThreadChannelClient extends EventEmitter<ThreadChannelEvents> {
  private joined = false;
  private joinPromise: Promise<void> | null = null;
  private typingTimers = new Map<string, ReturnType<typeof setTimeout>>();

  constructor(private readonly channel: Channel, public readonly threadId: string) {
    super();
    this.attachChannelHandlers();
  }

  private attachChannelHandlers() {
    this.channel.on('new_message', (payload) => {
      const message = normalizeSocketMessage(payload, this.threadId);
      if (message) {
        this.emit('message', message);
      }
    });

    this.channel.on('message_edited', (payload) => {
      const message = normalizeMessageEdit(payload, this.threadId);
      if (message) {
        this.emit('message_updated', message);
      }
    });

    this.channel.on('message_deleted', (payload) => {
      if (payload?.id) {
        this.emit('message_deleted', payload.id);
      }
    });

    this.channel.on('message_read', (payload) => {
      if (payload?.user_id && payload?.message_id && payload?.read_at) {
        this.emit('read_receipt', {
          userId: String(payload.user_id),
          messageId: String(payload.message_id),
          readAt: new Date(payload.read_at).toISOString(),
        });
      }
    });

    this.channel.on('user_typing', (payload) => {
      if (!payload || typeof payload.user_id === 'undefined') return;
      const state: ThreadTypingState = {
        userId: String(payload.user_id),
        isTyping: Boolean(payload.is_typing),
        timestamp: typeof payload.timestamp === 'number' ? payload.timestamp : Date.now(),
      };
      this.emit('typing', state);
      this.trackTypingTimeout(state);
    });

    this.channel.on('presence_state', (payload) => {
      this.emit('presence_state', payload ?? {});
    });

    this.channel.on('presence_diff', (payload) => {
      this.emit('presence_diff', payload ?? {});
    });

    this.channel.onError((error) => {
      this.emit('error', normalizeError(error));
    });

    this.channel.onClose(() => {
      this.joined = false;
    });
  }

  private trackTypingTimeout(state: ThreadTypingState) {
    if (!state.isTyping) {
      const timer = this.typingTimers.get(state.userId);
      if (timer) {
        clearTimeout(timer);
        this.typingTimers.delete(state.userId);
      }
      return;
    }

    const timer = setTimeout(() => {
      this.typingTimers.delete(state.userId);
      this.emit('typing', {
        userId: state.userId,
        isTyping: false,
        timestamp: Date.now(),
      });
    }, 3_500);
    this.typingTimers.set(state.userId, timer);
  }

  async ensureJoined(): Promise<void> {
    if (this.joined) return;
    if (this.joinPromise) return this.joinPromise;

    this.joinPromise = new Promise((resolve, reject) => {
      this.channel
        .join()
        .receive('ok', () => {
          this.joined = true;
          resolve();
        })
        .receive('error', (error) => {
          const normalized = normalizeError(error);
          this.emit('error', normalized);
          reject(normalized);
        })
        .receive('timeout', () => {
          const timeoutError = new Error('Timed out joining thread channel');
          this.emit('error', timeoutError);
          reject(timeoutError);
        });
    }).finally(() => {
      this.joinPromise = null;
    });

    return this.joinPromise;
  }

  async leave(): Promise<void> {
    if (!this.joined) return;
    await this.channel.leave();
    this.joined = false;
    for (const timer of this.typingTimers.values()) {
      clearTimeout(timer);
    }
    this.typingTimers.clear();
  }

  async sendMessage(options: SendMessageOptions): Promise<{ id: string; timestamp: number }> {
    await this.ensureJoined();

    const payload: Record<string, unknown> = {
      content: options.content,
      content_type: options.contentType ?? 'text',
      media_url: options.mediaUrl,
      media_mime_type: options.mediaMimeType,
      media_size: options.mediaSize,
      reply_to_id: options.replyToId,
      client_created_at: new Date().toISOString(),
    };

    if (options.attachments && options.attachments.length > 0) {
      payload.attachments = options.attachments.map((attachment) => ({
        url: attachment.url,
        mime_type: attachment.mimeType,
        size: attachment.size,
        width: attachment.width,
        height: attachment.height,
        thumbnail_url: attachment.thumbnailUrl,
      }));
    }

    return new Promise((resolve, reject) => {
      this.channel
        .push('new_message', payload, 10_000)
        .receive('ok', (response) => {
          resolve({
            id: String(response?.id ?? ''),
            timestamp: Number(response?.timestamp ?? Date.now()),
          });
        })
        .receive('error', (error) => {
          reject(normalizeError(error));
        })
        .receive('timeout', () => {
          reject(new Error('Timed out sending message'));
        });
    });
  }

  async markRead(messageId: string) {
    await this.ensureJoined();
    this.channel.push('mark_read', { message_id: messageId });
  }

  async setTyping(isTyping: boolean) {
    await this.ensureJoined();
    this.channel.push('typing', { is_typing: isTyping });
  }

  async cdcPull(options: { since?: string | number | null }): Promise<{ changes: unknown[]; nextCursor: number | string | null }> {
    await this.ensureJoined();
    const payload: Record<string, unknown> = {};
    if (typeof options.since !== 'undefined' && options.since !== null) {
      payload.since = options.since;
    }
    return new Promise((resolve, reject) => {
      this.channel
        .push('cdc:pull', payload, 10_000)
        .receive('ok', (response: any) => {
          const changes = Array.isArray(response?.changes)
            ? (response.changes as unknown[])
            : Array.isArray(response?.logs)
              ? (response.logs as unknown[])
              : [];
          const nextCursor = (response?.next_cursor ?? response?.nextCursor ?? null) as number | string | null;
          resolve({ changes, nextCursor });
        })
        .receive('error', (error) => reject(normalizeError(error)))
        .receive('timeout', () => reject(new Error('Timed out pulling CDC changes')));
    });
  }

  async cdcPush(changes: Array<Record<string, unknown>>): Promise<{ applied: number; failed: number }> {
    await this.ensureJoined();
    return new Promise((resolve, reject) => {
      this.channel
        .push('cdc:push', { logs: changes }, 15_000)
        .receive('ok', (response: any) => {
          resolve({ applied: Number(response?.applied ?? 0), failed: Number(response?.failed ?? 0) });
        })
        .receive('error', (error) => reject(normalizeError(error)))
        .receive('timeout', () => reject(new Error('Timed out pushing CDC changes')));
    });
  }
}

interface ThreadRegistryEntry {
  client: ThreadChannelClient;
  refCount: number;
}

interface RealtimeEvents {
  status: (status: ConnectionStatus) => void;
  error: (error: Error) => void;
}

export class RealtimeService extends EventEmitter<RealtimeEvents> {
  private socket: Socket | null = null;
  private status: ConnectionStatus = 'disconnected';
  private accessToken: string | null = null;
  private threadRegistry = new Map<string, ThreadRegistryEntry>();

  constructor() {
    super();
  }

  get currentStatus() {
    return this.status;
  }

  connect(token: string) {
    this.accessToken = token;
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
    this.status = 'connecting';
    this.emit('status', this.status);

    this.socket = new PhoenixSocket(realtimeConfig.socketUrl, {
      params: () => ({
        token: this.accessToken,
      }),
      heartbeatIntervalMs: realtimeConfig.heartbeatIntervalMs,
    });

    this.socket.onOpen(() => {
      this.status = 'connected';
      this.emit('status', this.status);
    });

    this.socket.onError((error) => {
      this.status = 'error';
      this.emit('status', this.status);
      this.emit('error', normalizeError(error));
    });

    this.socket.onClose(() => {
      this.status = 'disconnected';
      this.emit('status', this.status);
      this.threadRegistry.forEach((entry) => entry.client.removeAllListeners());
    });

    this.socket.connect();
  }

  disconnect() {
    this.threadRegistry.forEach(async (entry) => {
      await entry.client.leave();
    });
    this.threadRegistry.clear();
    this.socket?.disconnect();
    this.socket = null;
    this.status = 'disconnected';
    this.emit('status', this.status);
  }

  updateToken(token: string) {
    this.accessToken = token;
    if (this.status === 'connected' || this.status === 'connecting') {
      this.socket?.disconnect();
      this.connect(token);
    }
  }

  joinThread(threadId: string): ThreadChannelClient {
    if (!threadId) {
      throw new Error('Thread ID is required to join thread channel.');
    }

    if (!this.socket) {
      if (!this.accessToken) {
        throw new Error('Realtime service not connected: missing access token');
      }
      this.connect(this.accessToken);
    }

    const existing = this.threadRegistry.get(threadId);
    if (existing) {
      existing.refCount += 1;
      void existing.client.ensureJoined();
      return existing.client;
    }

    const channel = this.socket!.channel(`thread:${threadId}`);
    const client = new ThreadChannelClient(channel, threadId);
    this.threadRegistry.set(threadId, { client, refCount: 1 });
    void client.ensureJoined();
    return client;
  }

  async leaveThread(threadId: string) {
    const entry = this.threadRegistry.get(threadId);
    if (!entry) return;
    entry.refCount -= 1;
    if (entry.refCount <= 0) {
      await entry.client.leave();
      this.threadRegistry.delete(threadId);
    }
  }
}

export function normalizeSocketMessage(payload: unknown, fallbackThreadId: string): ApiMessage | null {
  if (!payload || typeof payload !== 'object') return null;
  const record = payload as Record<string, unknown>;

  const id = String(record.id ?? '');
  const threadId = String(record.thread_id ?? fallbackThreadId ?? '');
  if (!id || !threadId) return null;

  const insertedAt = parseTimestamp(record.created_at ?? record.inserted_at ?? Date.now());
  const updatedAt = parseTimestamp(record.updated_at ?? record.created_at ?? Date.now());

  return {
    id,
    threadId,
    senderId: record.sender_id ? String(record.sender_id) : '',
    content: typeof record.content === 'string' ? record.content : null,
    contentType: (record.content_type as ApiMessage['contentType']) ?? 'text',
    mediaUrl: record.media_url ? String(record.media_url) : null,
    mediaMimeType: record.media_mime_type ? String(record.media_mime_type) : null,
    mediaSize: typeof record.media_size === 'number' ? record.media_size : null,
    replyToId: record.reply_to_id ? String(record.reply_to_id) : null,
    isDeleted: Boolean(record.is_deleted),
    deletedAt: record.deleted_at ? parseTimestamp(record.deleted_at) : null,
    editedAt: record.edited_at ? parseTimestamp(record.edited_at) : null,
    clientCreatedAt: record.client_created_at ? parseTimestamp(record.client_created_at) : null,
    insertedAt,
    updatedAt,
    attachments: Array.isArray(record.attachments)
      ? record.attachments
          .map((attachment) => normalizeAttachment(attachment))
          .filter((item): item is NonNullable<ApiMessage['attachments']>[number] => Boolean(item))
      : [],
    sender: record.sender && typeof record.sender === 'object' ? (record.sender as ApiMessage['sender']) : undefined,
  };
}

export function normalizeMessageEdit(payload: unknown, fallbackThreadId: string): ApiMessage | null {
  if (!payload || typeof payload !== 'object') return null;
  const record = payload as Record<string, unknown>;
  if (!record.id) return null;
  const base = normalizeSocketMessage(payload, fallbackThreadId);
  if (!base) return null;
  return {
    ...base,
    content: typeof record.content === 'string' ? record.content : base.content,
    editedAt: parseTimestamp(record.edited_at ?? Date.now()),
  };
}

function parseTimestamp(input: unknown): string {
  if (typeof input === 'string') {
    const date = new Date(input);
    if (!Number.isNaN(date.getTime())) {
      return date.toISOString();
    }
  }
  if (typeof input === 'number') {
    const date = new Date(input);
    if (!Number.isNaN(date.getTime())) {
      return date.toISOString();
    }
  }
  return new Date().toISOString();
}

function normalizeAttachment(input: unknown) {
  if (!input || typeof input !== 'object') return null;
  const record = input as Record<string, unknown>;
  if (!record.url) return null;
  return {
    id: record.id ? String(record.id) : String(record.url),
    url: String(record.url),
    mimeType: record.mime_type ? String(record.mime_type) : 'application/octet-stream',
    size: typeof record.size === 'number' ? record.size : undefined,
    width: typeof record.width === 'number' ? record.width : undefined,
    height: typeof record.height === 'number' ? record.height : undefined,
    thumbnailUrl: record.thumbnail_url ? String(record.thumbnail_url) : undefined,
  };
}

function normalizeError(error: unknown): Error {
  if (error instanceof Error) return error;
  if (typeof error === 'string') return new Error(error);
  if (error && typeof error === 'object' && 'reason' in error) {
    return new Error(String((error as { reason: unknown }).reason));
  }
  return new Error('Realtime operation failed');
}
