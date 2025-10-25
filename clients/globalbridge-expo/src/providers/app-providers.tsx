import { PropsWithChildren } from 'react';

import { QueryProvider } from '~/providers/query-provider';
import { NotificationProvider } from '~/providers/notification-provider';
import { RealtimeProvider } from '~/providers/realtime-provider';
import { SessionProvider } from '~/providers/session-provider';

export function AppProviders({ children }: PropsWithChildren) {
  return (
    <QueryProvider>
      <SessionProvider>
        <NotificationProvider>
          <RealtimeProvider>{children}</RealtimeProvider>
        </NotificationProvider>
      </SessionProvider>
    </QueryProvider>
  );
}
