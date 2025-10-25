import { createContext, useContext, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';

import { useSession } from '~/hooks/use-session';
import { RealtimeService, type ConnectionStatus, type ThreadChannelClient, type UserChannelClient } from '~/services/realtime-service';

interface RealtimeContextValue {
  service: RealtimeService;
  status: ConnectionStatus;
  joinThread: (threadId: string) => ThreadChannelClient;
  leaveThread: (threadId: string) => Promise<void>;
  joinUserChannel: (userId: string) => UserChannelClient;
  leaveUserChannel: () => void;
}

const RealtimeContext = createContext<RealtimeContextValue | null>(null);

export function RealtimeProvider({ children }: { children: ReactNode }) {
  const service = useMemo(() => new RealtimeService(), []);
  const [status, setStatus] = useState<ConnectionStatus>(service.currentStatus);

  const session = useSession((state) => ({
    status: state.status,
    accessToken: state.tokens?.accessToken,
  }));

  useEffect(() => {
    function handleStatus(next: ConnectionStatus) {
      setStatus(next);
    }
    function handleError(error: Error) {
      console.warn('[realtime-provider] Error', error);
    }

    service.on('status', handleStatus);
    service.on('error', handleError);

    return () => {
      service.off('status', handleStatus);
      service.off('error', handleError);
      service.disconnect();
    };
  }, [service]);

  useEffect(() => {
    if (session.status === 'authenticated' && session.accessToken) {
      service.connect(session.accessToken);
    } else {
      service.disconnect();
    }
  }, [service, session.accessToken, session.status]);

  const value = useMemo<RealtimeContextValue>(
    () => ({
      service,
      status,
      joinThread: (threadId: string) => service.joinThread(threadId),
      leaveThread: (threadId: string) => service.leaveThread(threadId),
      joinUserChannel: (userId: string) => service.joinUserChannel(userId),
      leaveUserChannel: () => service.leaveUserChannel(),
    }),
    [service, status],
  );

  return <RealtimeContext.Provider value={value}>{children}</RealtimeContext.Provider>;
}

export function useRealtime() {
  const context = useContext(RealtimeContext);
  if (!context) {
    throw new Error('useRealtime must be used within a RealtimeProvider');
  }
  return context;
}
