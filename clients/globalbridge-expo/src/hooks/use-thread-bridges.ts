import { useCallback, useEffect, useState } from 'react';

import { useSession } from '~/hooks/use-session';
import { getTelegramBridgeForThread, type ApiBridge } from '~/api/endpoints';

export interface ThreadBridgeInfo {
  threadId: string;
  bridge: ApiBridge | null;
  isLoading: boolean;
}

export function useThreadBridges(threadIds: string[]): Record<string, ThreadBridgeInfo> {
  const { client } = useSession();
  const [bridgeInfo, setBridgeInfo] = useState<Record<string, ThreadBridgeInfo>>({});

  const fetchBridgeForThread = useCallback(async (threadId: string) => {
    if (!client) return;

    setBridgeInfo(prev => ({
      ...prev,
      [threadId]: { threadId, bridge: null, isLoading: true }
    }));

    try {
      const bridge = await getTelegramBridgeForThread(client, threadId);
      setBridgeInfo(prev => ({
        ...prev,
        [threadId]: { threadId, bridge, isLoading: false }
      }));
    } catch (error) {
      setBridgeInfo(prev => ({
        ...prev,
        [threadId]: { threadId, bridge: null, isLoading: false }
      }));
    }
  }, [client]);

  useEffect(() => {
    // Fetch bridge info for all thread IDs
    threadIds.forEach(threadId => {
      if (!bridgeInfo[threadId]) {
        fetchBridgeForThread(threadId);
      }
    });
  }, [threadIds, fetchBridgeForThread, bridgeInfo]);

  return bridgeInfo;
}