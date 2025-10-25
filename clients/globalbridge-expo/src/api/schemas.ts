import { z } from 'zod';

export const isoDateString = z.string().datetime({ offset: true });

export const UserSchema = z.object({
  id: z.string(),
  email: z.string().email().optional().nullable(),
  username: z.string().optional().nullable(),
  displayName: z.string().optional().nullable(),
  avatarUrl: z.string().url().optional().nullable(),
  statusMessage: z.string().optional().nullable(),
  lastSeenAt: isoDateString.optional().nullable(),
  isOnline: z.boolean().optional(),
  tier: z.enum(['free', 'pro', 'enterprise']).optional(),
});

export const ThreadParticipantSchema = z.object({
  id: z.string(),
  user: UserSchema,
  role: z.enum(['member', 'admin']).default('member'),
  mutedUntil: isoDateString.optional().nullable(),
});

export const ThreadSchema = z.object({
  id: z.string(),
  title: z.string().optional().nullable(),
  threadType: z.enum(['direct', 'group']),
  avatarUrl: z.string().optional().nullable(),
  lastMessageAt: isoDateString,
  databaseShardId: z.string(),
  isArchived: z.boolean().default(false),
  isMuted: z.boolean().default(false),
  participants: z.array(ThreadParticipantSchema).default([]),
});

export const AttachmentSchema = z.object({
  id: z.string(),
  url: z.string().url(),
  mimeType: z.string(),
  size: z.number().optional(),
  width: z.number().optional(),
  height: z.number().optional(),
  thumbnailUrl: z.string().url().optional().nullable(),
});

export const MessageSchema = z.object({
  id: z.string(),
  threadId: z.string(),
  senderId: z.string(),
  content: z.string().optional().nullable(),
  contentType: z.enum(['text', 'image', 'video', 'audio', 'file', 'location']),
  mediaUrl: z.string().url().optional().nullable(),
  mediaMimeType: z.string().optional().nullable(),
  mediaSize: z.number().optional().nullable(),
  replyToId: z.string().optional().nullable(),
  isDeleted: z.boolean().default(false),
  deletedAt: isoDateString.optional().nullable(),
  editedAt: isoDateString.optional().nullable(),
  clientCreatedAt: isoDateString.optional().nullable(),
  insertedAt: isoDateString,
  updatedAt: isoDateString,
  attachments: z.array(AttachmentSchema).default([]),
  sender: UserSchema.optional(),
});

export const CDCEntrySchema = z.object({
  id: z.union([z.string(), z.number()]),
  tableName: z.string(),
  recordId: z.string(),
  operation: z.enum(['INSERT', 'UPDATE', 'DELETE']),
  oldData: z.record(z.any()).optional().nullable(),
  newData: z.record(z.any()).optional().nullable(),
  changedFields: z.array(z.string()).optional().nullable(),
  timestamp: isoDateString,
});

export const PaginatedMetaSchema = z.object({
  nextCursor: z.string().optional().nullable(),
  prevCursor: z.string().optional().nullable(),
});

export const createPaginatedSchema = <T extends z.ZodTypeAny>(item: T) =>
  z.object({
    data: z.array(item),
    nextCursor: z.string().optional().nullable(),
    prevCursor: z.string().optional().nullable(),
  });

export type ApiUser = z.infer<typeof UserSchema>;
export type ApiThread = z.infer<typeof ThreadSchema>;
export type ApiThreadParticipant = z.infer<typeof ThreadParticipantSchema>;
export type ApiMessage = z.infer<typeof MessageSchema>;
export type ApiAttachment = z.infer<typeof AttachmentSchema>;
export type ApiCDCEntry = z.infer<typeof CDCEntrySchema>;
export const BridgeSchema = z.object({
  id: z.string(),
  user_id: z.string(),
  bridge_type: z.enum(['whatsapp', 'telegram']),
  phone_number: z.string(),
  status: z.enum(['connected', 'disconnected', 'error', 'connecting']),
  last_connected_at: isoDateString.optional().nullable(),
  error_message: z.string().optional().nullable(),
  qr_code: z.string().optional().nullable(),
  is_active: z.boolean(),
  created_at: isoDateString,
  updated_at: isoDateString,
});

export const BridgesResponseSchema = z.object({
  data: z.array(BridgeSchema),
});

export const SingleBridgeSchema = z.object({
  data: BridgeSchema,
});

export const CreateBridgePayloadSchema = z.object({
  bridge_type: z.enum(['whatsapp', 'telegram']),
  phone_number: z.string(),
});

export const UpdateBridgePayloadSchema = z.object({
  phone_number: z.string().optional(),
  is_active: z.boolean().optional(),
});

export const BridgeStatsSchema = z.object({
  data: z.object({
    total_bridges: z.number(),
    active_bridges: z.number(),
    bridges_by_status: z.record(z.number()),
  }),
});

export type ApiBridge = z.infer<typeof BridgeSchema>;
export type ApiBridgesResponse = z.infer<typeof BridgesResponseSchema>;
export type ApiSingleBridge = z.infer<typeof SingleBridgeSchema>;
export type CreateBridgePayload = z.infer<typeof CreateBridgePayloadSchema>;
export type UpdateBridgePayload = z.infer<typeof UpdateBridgePayloadSchema>;
export type ApiBridgeStats = z.infer<typeof BridgeStatsSchema>;

export type ApiPaginated<T> = {
  data: T[];
  nextCursor?: string | null;
  prevCursor?: string | null;
};
