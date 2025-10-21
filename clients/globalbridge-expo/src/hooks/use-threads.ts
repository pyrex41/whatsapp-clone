import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  useInfiniteQuery,
  useQuery,
  useQueryClient,
  type UseInfiniteQueryResult,
  type QueryClient,
} from '@tanstack/react-query';

import { apiClient } from '~/api/client';
import { listMessages, listThreads } from '~/api/endpoints';
import type { ApiMessage, ApiThread } from '~/api/schemas';
import {
  fetchCachedMessages,
  fetchCachedThreads,
  upsertMessages,
  upsertThreads,
} from '~/storage/cdc-database';
import { useThreadCdcSync } from '~/hooks/use-thread-sync';
import { useRealtime } from '~/providers/realtime-provider';
import type {
  ConnectionStatus,
  SendMessageOptions,
  ThreadTypingState,
} from '~/services/realtime-service';
import { useSession } from '~/hooks/use-session';

type MessagesPage = { items: ApiMessage[]; nextCursor: string | null };
type MessagesPagesData = { pages: MessagesPage[]; pageParams: unknown[] };

export interface ThreadRealtimeHandle {
  sendMessage: (options: SendMessageOptions) => Promise<{ id: string; timestamp: number }>;
  markRead: (messageId: string) => Promise<void>;
  setTyping: (isTyping: boolean) => Promise<void>;
  typingUsers: string[];
  status: ConnectionStatus;
}

const TYPING_EXPIRATION_MS = 4_500;

type MessagesQueryResult = UseInfiniteQueryResult<{ items: ApiMessage[]; nextCursor: string | null }, Error>;

export type ThreadMessagesResult = MessagesQueryResult & { realtime: ThreadRealtimeHandle };

function updateMessageQueries(
  queryClient: QueryClient,
  threadId: string,
  updater: (data: MessagesPagesData) => MessagesPagesData,
) {
  const queries = queryClient.getQueriesData<MessagesPagesData>({ queryKey: ['threads', threadId, 'messages'] });
  for (const [key, data] of queries) {
    if (!data) continue;
    const next = updater(data);
    queryClient.setQueryData(key, next);
  }
}

function withSortedMessage(existing: ApiMessage[], message: ApiMessage) {
  const filtered = existing.filter((item) => item.id !== message.id);
  filtered.push(message);
  filtered.sort((a, b) => {
    if (a.insertedAt === b.insertedAt) {
      return a.id > b.id ? -1 : 1;
    }
    return a.insertedAt > b.insertedAt ? -1 : 1;
  });
  return filtered;
}

function withRemovedMessage(existing: ApiMessage[], messageId: string) {
  return existing.filter((item) => item.id !== messageId);
}

function withPatchedMessage(existing: ApiMessage[], patch: Partial<ApiMessage> & { id: string }) {
  const next = existing.map((item) => (item.id === patch.id ? { ...item, ...patch } : item));
  return next.sort((a, b) => {
    if (a.insertedAt === b.insertedAt) {
      return a.id > b.id ? -1 : 1;
    }
    return a.insertedAt > b.insertedAt ? -1 : 1;
  });
}

function insertMessageIntoPages(data: MessagesPagesData, message: ApiMessage): MessagesPagesData {
  if (data.pages.length === 0) {
    return {
      pages: [{ items: [message], nextCursor: null }],
      pageParams: [null],
    };
  }

  const [first, ...rest] = data.pages;
  const nextFirst = {
    ...first,
    items: withSortedMessage(first.items, message),
  };
  const pages = [nextFirst, ...rest.map((page) => ({ ...page, items: withRemovedMessage(page.items, message.id) }))];
  return {
    pages,
    pageParams: data.pageParams,
  };
}

function patchMessageInPages(data: MessagesPagesData, message: Partial<ApiMessage> & { id: string }): MessagesPagesData {
  return {
    pages: data.pages.map((page) => ({
      ...page,
      items: withPatchedMessage(page.items, message),
    })),
    pageParams: data.pageParams,
  };
}

function removeMessageFromPages(data: MessagesPagesData, messageId: string): MessagesPagesData {
  return {
    pages: data.pages.map((page) => ({
      ...page,
      items: withRemovedMessage(page.items, messageId),
    })),
    pageParams: data.pageParams,
  };
}

function updateThreadLists(queryClient: QueryClient, threadId: string, lastMessageAt: string) {
  const queries = queryClient.getQueriesData<ApiThread[]>({ queryKey: ['threads'] });
  for (const [key, threads] of queries) {
    if (!threads) continue;
    const index = threads.findIndex((thread) => thread.id === threadId);
    if (index === -1) continue;
    const updatedThread: ApiThread = {
      ...threads[index],
      lastMessageAt,
    };
    const next = [updatedThread, ...threads.filter((_, idx) => idx !== index)];
    queryClient.setQueryData(key, next);
  }
}

function useRealtimeThreadSync(
  threadId: string,
  currentUser: { id: string; email?: string; displayName?: string } | undefined,
): ThreadRealtimeHandle {
  const { joinThread, leaveThread, status } = useRealtime();
  const queryClient = useQueryClient();
  const subscriptionRef = useRef<ReturnType<typeof joinThread> | null>(null);
  const typingStateRef = useRef<Map<string, number>>(new Map());
  const [typingUsers, setTypingUsers] = useState<string[]>([]);

  useEffect(() => {
    if (!threadId) return;
    const client = joinThread(threadId);
    subscriptionRef.current = client;
    const typingMap = typingStateRef.current;

    const handleMessage = (message: ApiMessage) => {
      void upsertMessages([message]);
      updateThreadLists(queryClient, message.threadId, message.insertedAt);
      updateMessageQueries(queryClient, threadId, (data) => insertMessageIntoPages(data, message));
    };

    const handleMessageUpdated = (message: ApiMessage) => {
      updateMessageQueries(queryClient, threadId, (data) => patchMessageInPages(data, message));
    };

    const handleMessageDeleted = (messageId: string) => {
      updateMessageQueries(queryClient, threadId, (data) => removeMessageFromPages(data, messageId));
    };

    const handleTyping = (state: ThreadTypingState) => {
      const map = typingStateRef.current;
      if (!state.isTyping) {
        map.delete(state.userId);
      } else {
        map.set(state.userId, state.timestamp ?? Date.now());
      }
      setTypingUsers(Array.from(map.keys()));
    };

    client.on('message', handleMessage);
    client.on('message_updated', handleMessageUpdated);
    client.on('message_deleted', handleMessageDeleted);
    client.on('typing', handleTyping);

    return () => {
      client.off('message', handleMessage);
      client.off('message_updated', handleMessageUpdated);
      client.off('message_deleted', handleMessageDeleted);
      client.off('typing', handleTyping);
      subscriptionRef.current = null;
      typingMap.clear();
      setTypingUsers([]);
      void leaveThread(threadId);
    };
  }, [joinThread, leaveThread, queryClient, threadId]);

  useEffect(() => {
    if (!typingUsers.length) return;
    const timer = setInterval(() => {
      const now = Date.now();
      const map = typingStateRef.current;
      let changed = false;
      for (const [userId, timestamp] of map.entries()) {
        if (now - timestamp > TYPING_EXPIRATION_MS) {
          map.delete(userId);
          changed = true;
        }
      }
      if (changed) {
        setTypingUsers(Array.from(map.keys()));
      }
    }, 1_000);
    return () => clearInterval(timer);
  }, [typingUsers.length]);

  const sendMessage = useCallback(
    async (options: SendMessageOptions) => {
      if (!subscriptionRef.current) {
        throw new Error('Thread not joined');
      }
      const nowIso = new Date().toISOString();
      const tempId = `temp-${Date.now()}`;
      const optimisticSender: ApiMessage['sender'] = currentUser
        ? {
            id: currentUser.id,
            email: currentUser.email,
            displayName: currentUser.displayName,
          }
        : undefined;

      const optimistic: ApiMessage = {
        id: tempId,
        threadId,
        senderId: currentUser?.id ?? 'local-user',
        content: options.content,
        contentType: options.contentType ?? 'text',
        mediaUrl: options.mediaUrl ?? null,
        mediaMimeType: options.mediaMimeType ?? null,
        mediaSize: options.mediaSize ?? null,
        replyToId: options.replyToId ?? null,
        isDeleted: false,
        deletedAt: null,
        editedAt: null,
        clientCreatedAt: nowIso,
        insertedAt: nowIso,
        updatedAt: nowIso,
        attachments: [],
        sender: optimisticSender,
      } as ApiMessage;

      updateThreadLists(queryClient, threadId, nowIso);
      updateMessageQueries(queryClient, threadId, (data) => insertMessageIntoPages(data, optimistic));

      try {
        const response = await subscriptionRef.current.sendMessage(options);
        const serverTimestamp = new Date(response.timestamp).toISOString();
        updateMessageQueries(queryClient, threadId, (data) => removeMessageFromPages(data, tempId));
        const finalMessage: ApiMessage = {
          ...optimistic,
          id: response.id,
          insertedAt: serverTimestamp,
          updatedAt: serverTimestamp,
          clientCreatedAt: optimistic.clientCreatedAt,
        };
        updateMessageQueries(queryClient, threadId, (data) => insertMessageIntoPages(data, finalMessage));
        void upsertMessages([finalMessage]);
        updateThreadLists(queryClient, threadId, serverTimestamp);
        return response;
      } catch (error) {
        updateMessageQueries(queryClient, threadId, (data) => removeMessageFromPages(data, tempId));
        throw error;
      }
    },
    [currentUser, queryClient, threadId],
  );

  const markRead = useCallback((messageId: string) => {
    if (!subscriptionRef.current) return Promise.resolve();
    return subscriptionRef.current.markRead(messageId);
  }, []);

  const setTyping = useCallback((isTyping: boolean) => {
    if (!subscriptionRef.current) return Promise.resolve();
    return subscriptionRef.current.setTyping(isTyping);
  }, []);

  return {
    sendMessage,
    markRead,
    setTyping,
    typingUsers,
    status,
  };
}

export function useThreads(options?: { includeArchived?: boolean }) {
  const queryClient = useQueryClient();

  const sortThreads = useCallback((threads: ApiThread[]) => {
    return [...threads].sort((a, b) => {
      const aTime = a.lastMessageAt ?? '';
      const bTime = b.lastMessageAt ?? '';
      return aTime > bTime ? -1 : 1;
    });
  }, []);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const cached = await fetchCachedThreads();
      if (!cancelled && cached.length > 0) {
        queryClient.setQueryData<ApiThread[]>(
          ['threads', options?.includeArchived ?? false],
          sortThreads(cached),
        );
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [options?.includeArchived, queryClient, sortThreads]);

  return useQuery<ApiThread[]>({
    queryKey: ['threads', options?.includeArchived ?? false],
    queryFn: () => listThreads(apiClient, { includeArchived: options?.includeArchived }),
    select: sortThreads,
    onSuccess: (threads) => {
      void upsertThreads(sortThreads(threads));
    },
  });
}

export function useThreadMessages(threadId: string, pageSize = 50): ThreadMessagesResult {
  const queryClient = useQueryClient();
  const currentUser = useSession((state) => state.tokens?.user);
  const realtime = useRealtimeThreadSync(threadId, currentUser ?? undefined);

  useThreadCdcSync(threadId, pageSize);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const cached = await fetchCachedMessages({ threadId, limit: pageSize });
      if (cancelled || cached.length === 0) return;
      queryClient.setQueryData(
        ['threads', threadId, 'messages', pageSize],
        {
          pages: [{ items: cached, nextCursor: null }],
          pageParams: [null],
        },
      );
    })();
    return () => {
      cancelled = true;
    };
  }, [pageSize, queryClient, threadId]);

  const query = useInfiniteQuery<{ items: ApiMessage[]; nextCursor: string | null }, Error>({
    queryKey: ['threads', threadId, 'messages', pageSize],
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam }) => {
      const response = await listMessages(apiClient, {
        threadId,
        cursor: pageParam,
        limit: pageSize,
      });
      if (!pageParam) {
        void upsertMessages(response.data);
      } else if (response.data.length > 0) {
        void upsertMessages(response.data);
      }
      return { items: response.data, nextCursor: response.nextCursor ?? null };
    },
    getNextPageParam: (lastPage) => lastPage.nextCursor,
  });

  return {
    ...query,
    realtime,
  } satisfies ThreadMessagesResult;
}

export function useFlattenedMessages(threadId: string, pageSize = 50) {
  const query = useThreadMessages(threadId, pageSize);
  const items = useMemo(() => {
    if (!query.data) return [] as ApiMessage[];
    return query.data.pages.flatMap((page) => page.items);
  }, [query.data]);

  return { ...query, items };
}
