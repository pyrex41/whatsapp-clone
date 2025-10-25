import { z } from 'zod';

import { ApiClient } from '~/api/client';
import {
  ApiBridge,
  ApiBridgeStats,
  ApiCDCEntry,
  ApiMessage,
  ApiPaginated,
  ApiThread,
  ApiUser,
  BridgeSchema,
  BridgesResponseSchema,
  CreateBridgePayload,
  MessageSchema,
  SingleBridgeSchema,
  ThreadSchema,
  UpdateBridgePayload,
  UserSchema,
  createPaginatedSchema,
  CDCEntrySchema,
} from '~/api/schemas';

const ThreadsResponseSchema = z.object({
  data: z.array(ThreadSchema),
});

const PaginatedMessagesSchema = createPaginatedSchema(MessageSchema);

const CurrentUserSchema = z.object({
  data: UserSchema,
});

const SingleMessageSchema = z.object({
  data: MessageSchema,
});

// Accept both camelCase and snake_case for next cursor to match backend
const CdcPullResponseSchema = z.union([
  z.object({
    data: z.object({
      changes: z.array(CDCEntrySchema),
      nextCursor: z.union([z.number(), z.string()]).optional().nullable(),
    }),
  }),
  z.object({
    data: z.object({
      changes: z.array(CDCEntrySchema),
      next_cursor: z.union([z.number(), z.string()]).optional().nullable(),
    }),
  }),
]);

export interface ListThreadsParams {
  cursor?: string | null;
  limit?: number;
  includeArchived?: boolean;
}

export interface ListMessagesParams {
  threadId: string;
  cursor?: string | null;
  limit?: number;
}

export interface SendMessagePayload {
  threadId: string;
  content: string;
  contentType?: 'text' | 'image' | 'video' | 'audio' | 'file' | 'location';
  mediaUrl?: string;
  mediaMimeType?: string;
  replyToId?: string;
}

export interface PullCdcParams {
  threadId: string;
  lastSyncCursor?: number | string | null;
}

export interface PushCdcPayload {
  threadId: string;
  changes: Omit<ApiCDCEntry, 'id'>[];
}

export async function listThreads(client: ApiClient, params: ListThreadsParams = {}): Promise<ApiThread[]> {
  const response = await client.request({
    path: '/v1/threads',
    method: 'GET',
    query: {
      cursor: params.cursor ?? undefined,
      limit: params.limit ?? undefined,
      include_archived: params.includeArchived ?? undefined,
    },
    schema: ThreadsResponseSchema,
  });
  return response.data;
}

export async function getCurrentUser(client: ApiClient): Promise<ApiUser> {
  const response = await client.request({
    path: '/auth/me',
    method: 'GET',
    schema: CurrentUserSchema,
  });
  return response.data;
}

export async function listMessages(
  client: ApiClient,
  params: ListMessagesParams,
): Promise<ApiPaginated<ApiMessage>> {
  const response = await client.request({
    path: `/v1/threads/${params.threadId}/messages`,
    method: 'GET',
    query: {
      cursor: params.cursor ?? undefined,
      limit: params.limit ?? undefined,
    },
    schema: PaginatedMessagesSchema,
  });
  return {
    data: response.data,
    nextCursor: response.nextCursor ?? null,
    prevCursor: response.prevCursor ?? null,
  };
}

export async function sendMessage(client: ApiClient, payload: SendMessagePayload): Promise<ApiMessage> {
  return client.request({
    path: `/v1/threads/${payload.threadId}/messages`,
    method: 'POST',
    body: {
      content: payload.content,
      contentType: payload.contentType ?? 'text',
      mediaUrl: payload.mediaUrl,
      mediaMimeType: payload.mediaMimeType,
      replyToId: payload.replyToId,
    },
    schema: SingleMessageSchema,
  }).then((result) => result.data);
}

export async function markThreadRead(client: ApiClient, threadId: string) {
  await client.request({
    path: `/v1/threads/${threadId}/read`,
    method: 'POST',
  });
}

export async function pullCdcChanges(
  client: ApiClient,
  params: PullCdcParams,
): Promise<{ changes: ApiCDCEntry[]; nextCursor: number | string | null }> {
  const response = await client.request({
    path: '/v1/sync/pull',
    method: 'POST',
    body: {
      thread_id: params.threadId,
      last_sync_cursor: params.lastSyncCursor ?? null,
    },
    schema: CdcPullResponseSchema,
  });

  return {
    changes: (response as any).data.changes,
    nextCursor:
      (response as any).data.nextCursor ?? (response as any).data.next_cursor ?? null,
  };
}

export async function pushCdcChanges(client: ApiClient, payload: PushCdcPayload) {
  await client.request({
    path: '/v1/sync/push',
    method: 'POST',
    body: {
      thread_id: payload.threadId,
      changes: payload.changes.map((change) => ({
        table_name: change.tableName,
        record_id: change.recordId,
        operation: change.operation,
        old_data: change.oldData,
        new_data: change.newData,
        changed_fields: change.changedFields ?? null,
        timestamp: change.timestamp,
      })),
    },
  });
}

// Bridge endpoints
export async function listBridges(client: ApiClient): Promise<ApiBridge[]> {
  const response = await client.request({
    path: '/v1/bridges',
    method: 'GET',
    schema: BridgesResponseSchema,
  });
  return response.data;
}

export async function getBridge(client: ApiClient, bridgeId: string): Promise<ApiBridge> {
  const response = await client.request({
    path: `/v1/bridges/${bridgeId}`,
    method: 'GET',
    schema: SingleBridgeSchema,
  });
  return response.data;
}

export async function createBridge(client: ApiClient, payload: CreateBridgePayload): Promise<ApiBridge> {
  const response = await client.request({
    path: '/v1/bridges',
    method: 'POST',
    body: { bridge: payload },
    schema: SingleBridgeSchema,
  });
  return response.data;
}

export async function createTelegramBridge(client: ApiClient, payload: CreateBridgePayload): Promise<ApiBridge> {
  const response = await client.request({
    path: '/v1/bridges/telegram',
    method: 'POST',
    body: { bridge: payload },
    schema: SingleBridgeSchema,
  });
  return response.data;
}

export async function updateBridge(client: ApiClient, bridgeId: string, payload: UpdateBridgePayload): Promise<ApiBridge> {
  const response = await client.request({
    path: `/v1/bridges/${bridgeId}`,
    method: 'PUT',
    body: { bridge: payload },
    schema: SingleBridgeSchema,
  });
  return response.data;
}

export async function toggleBridgeActive(client: ApiClient, bridgeId: string, isActive: boolean): Promise<ApiBridge> {
  const response = await client.request({
    path: `/v1/bridges/${bridgeId}/toggle_active`,
    method: 'PATCH',
    body: { bridge: { is_active: isActive } },
    schema: SingleBridgeSchema,
  });
  return response.data;
}

export async function deleteBridge(client: ApiClient, bridgeId: string): Promise<void> {
  await client.request({
    path: `/v1/bridges/${bridgeId}`,
    method: 'DELETE',
  });
}

export async function getBridgeStats(client: ApiClient): Promise<ApiBridgeStats['data']> {
  const response = await client.request({
    path: '/v1/bridges/stats',
    method: 'GET',
    schema: z.object({
      data: z.object({
        total_bridges: z.number(),
        active_bridges: z.number(),
        bridges_by_status: z.record(z.number()),
      }),
    }),
  });
  return response.data;
}

export async function getTelegramBridgeForThread(client: ApiClient, threadId: string): Promise<ApiBridge | null> {
  try {
    const response = await client.request({
      path: `/v1/bridges/${threadId}/telegram`,
      method: 'GET',
      schema: SingleBridgeSchema,
    });
    return response.data;
  } catch (error) {
    // Return null if no bridge found for this thread
    return null;
  }
}
