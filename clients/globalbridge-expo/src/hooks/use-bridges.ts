import { useCallback, useEffect, useState } from 'react';

import { useSession } from '~/hooks/use-session';
import {
  createTelegramBridge,
  deleteBridge,
  listBridges,
  toggleBridgeActive,
  updateBridge,
  type ApiBridge,
  type CreateBridgePayload,
  type UpdateBridgePayload,
} from '~/api/endpoints';

export interface UseBridgesReturn {
  bridges: ApiBridge[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  createBridge: (payload: CreateBridgePayload) => Promise<ApiBridge>;
  updateBridge: (bridgeId: string, payload: UpdateBridgePayload) => Promise<ApiBridge>;
  toggleBridgeActive: (bridgeId: string, isActive: boolean) => Promise<ApiBridge>;
  deleteBridge: (bridgeId: string) => Promise<void>;
}

export function useBridges(): UseBridgesReturn {
  const { client } = useSession();
  const [bridges, setBridges] = useState<ApiBridge[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refetch = useCallback(async () => {
    if (!client) {
      setIsLoading(false);
      return;
    }

    try {
      setError(null);
      const bridgeList = await listBridges(client);
      setBridges(bridgeList);
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Failed to load bridges';
      setError(errorMessage);
      console.error('Failed to load bridges:', err);
    } finally {
      setIsLoading(false);
    }
  }, [client]);

  useEffect(() => {
    refetch();
  }, [refetch]);

  const handleCreateBridge = useCallback(async (payload: CreateBridgePayload): Promise<ApiBridge> => {
    if (!client) {
      throw new Error('No API client available');
    }

    const newBridge = await createTelegramBridge(client, payload);
    setBridges(prev => [...prev, newBridge]);
    return newBridge;
  }, [client]);

  const handleUpdateBridge = useCallback(async (bridgeId: string, payload: UpdateBridgePayload): Promise<ApiBridge> => {
    if (!client) {
      throw new Error('No API client available');
    }

    const updatedBridge = await updateBridge(client, bridgeId, payload);
    setBridges(prev => prev.map(bridge => bridge.id === bridgeId ? updatedBridge : bridge));
    return updatedBridge;
  }, [client]);

  const handleToggleBridgeActive = useCallback(async (bridgeId: string, isActive: boolean): Promise<ApiBridge> => {
    if (!client) {
      throw new Error('No API client available');
    }

    const updatedBridge = await toggleBridgeActive(client, bridgeId, isActive);
    setBridges(prev => prev.map(bridge => bridge.id === bridgeId ? updatedBridge : bridge));
    return updatedBridge;
  }, [client]);

  const handleDeleteBridge = useCallback(async (bridgeId: string): Promise<void> => {
    if (!client) {
      throw new Error('No API client available');
    }

    await deleteBridge(client, bridgeId);
    setBridges(prev => prev.filter(bridge => bridge.id !== bridgeId));
  }, [client]);

  return {
    bridges,
    isLoading,
    error,
    refetch,
    createBridge: handleCreateBridge,
    updateBridge: handleUpdateBridge,
    toggleBridgeActive: handleToggleBridgeActive,
    deleteBridge: handleDeleteBridge,
  };
}