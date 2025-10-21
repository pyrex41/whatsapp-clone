import { describe, expect, it } from 'vitest';

import { normalizeMessageEdit, normalizeSocketMessage } from '~/services/realtime-service';

describe('realtime message normalization', () => {
  it('normalizes basic socket payloads', () => {
    const payload = {
      id: 'msg-1',
      thread_id: 'thread-1',
      sender_id: 'user-1',
      content: 'Hello',
      content_type: 'text',
      created_at: '2024-10-20T12:00:00Z',
      attachments: [
        {
          url: 'https://example.com/file.jpg',
          mime_type: 'image/jpeg',
          size: 1024,
        },
      ],
    };

    const message = normalizeSocketMessage(payload, 'fallback-thread');

    expect(message).not.toBeNull();
    expect(message?.id).toBe('msg-1');
    expect(message?.threadId).toBe('thread-1');
    expect(message?.attachments).toHaveLength(1);
    expect(message?.attachments?.[0]).toMatchObject({
      url: 'https://example.com/file.jpg',
      mimeType: 'image/jpeg',
    });
  });

  it('falls back to defaults when fields missing', () => {
    const payload = {
      id: 'msg-2',
      sender_id: 'user-2',
    };

    const message = normalizeSocketMessage(payload, 'thread-2');

    expect(message).not.toBeNull();
    expect(message?.threadId).toBe('thread-2');
    expect(message?.contentType).toBe('text');
  });

  it('normalizes message edits', () => {
    const payload = {
      id: 'msg-3',
      thread_id: 'thread-3',
      sender_id: 'user-1',
      content: 'Updated',
      edited_at: '2024-10-21T10:00:00Z',
    };

    const message = normalizeMessageEdit(payload, 'thread-3');

    expect(message).not.toBeNull();
    expect(message?.content).toBe('Updated');
    expect(message?.editedAt).toBe('2024-10-21T10:00:00.000Z');
  });
});
