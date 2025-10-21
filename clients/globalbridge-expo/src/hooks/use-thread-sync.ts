import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { apiClient } from '~/api/client';
import { pullCdcChanges } from '~/api/endpoints';
import {
  applyCdcChanges,
  fetchCachedMessages,
  fetchCachedThreads,
  readCdcCursor,
  writeCdcCursor,
} from '~/storage/cdc-database';
import { useRealtime } from '~/providers/realtime-provider';
import type { ApiCDCEntry } from '~/api/schemas';

const SYNC_INTERVAL_MS = 10_000;

export function useThreadCdcSync(threadId: string, pageSize = 50) {
  const queryClient = useQueryClient();
  const { joinThread, leaveThread, status } = useRealtime();

  useEffect(() => {
    let cancelled = false;
    let timeoutHandle: ReturnType<typeof setTimeout> | null = null;

    async function runSync(previousCursor: number | string | null) {
      try {
        const cursor = previousCursor ?? (await readCdcCursor(threadId));
        let changes: ApiCDCEntry[] = [];
        let nextCursor: number | string | null = null;

        // Prefer realtime CDC when connected; fall back to HTTP
        if (status === 'connected') {
          const client = joinThread(threadId);
          const { changes: rawChanges, nextCursor: nc } = await client.cdcPull({ since: cursor ?? null });
          nextCursor = nc ?? cursor ?? null;

          // Transform raw changes into ApiCDCEntry shape
          if (Array.isArray(rawChanges) && rawChanges.length > 0) {
            changes = rawChanges
              .map((entry: any): ApiCDCEntry | null => {
                try {
                  return {
                    id: String(entry.id ?? ''),
                    tableName: String(entry.table_name ?? entry.tableName ?? ''),
                    recordId: String(entry.record_id ?? entry.recordId ?? ''),
                    operation: String(entry.operation ?? '').toUpperCase() as ApiCDCEntry['operation'],
                    oldData: entry.old_data ?? entry.oldData ?? null,
                    newData: entry.new_data ?? entry.newData ?? null,
                    changedFields: entry.changed_fields ?? entry.changedFields ?? null,
                    timestamp: typeof entry.timestamp === 'string' || typeof entry.timestamp === 'number' ? entry.timestamp : Date.now(),
                  } as ApiCDCEntry;
                } catch {
                  return null;
                }
              })
              .filter((x): x is ApiCDCEntry => Boolean(x));
          }
        } else {
          const res = await pullCdcChanges(apiClient, { threadId, lastSyncCursor: cursor });
          changes = res.changes;
          nextCursor = res.nextCursor ?? cursor ?? null;
        }

        if (changes.length > 0) {
          await applyCdcChanges(threadId, changes);
          await writeCdcCursor(threadId, nextCursor ?? cursor);
          const [threads, messages] = await Promise.all([
            fetchCachedThreads(),
            fetchCachedMessages({ threadId, limit: pageSize }),
          ]);
          queryClient.setQueryData(['threads', false], threads);
          queryClient.setQueryData(['threads', threadId, 'messages', pageSize], {
            pages: [{ items: messages, nextCursor: null }],
            pageParams: [null],
          });
          queryClient.invalidateQueries({ queryKey: ['threads'] });
          queryClient.invalidateQueries({ queryKey: ['threads', threadId, 'messages'] });
        }

        if (!cancelled) {
          timeoutHandle = setTimeout(() => runSync(nextCursor ?? cursor ?? null), SYNC_INTERVAL_MS);
        }
      } catch (error) {
        console.warn('[cdc-sync] Failed to synchronize thread', threadId, error);
        if (!cancelled) {
          timeoutHandle = setTimeout(() => runSync(previousCursor ?? null), SYNC_INTERVAL_MS * 2);
        }
      }
    }

    runSync(null);

    return () => {
      cancelled = true;
      if (timeoutHandle) {
        clearTimeout(timeoutHandle);
      }
      void leaveThread(threadId);
    };
  }, [joinThread, leaveThread, pageSize, queryClient, status, threadId]);
}
