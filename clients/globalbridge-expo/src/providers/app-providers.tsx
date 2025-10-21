import { PropsWithChildren } from 'react';

import { QueryProvider } from '~/providers/query-provider';
import { RealtimeProvider } from '~/providers/realtime-provider';
import { SessionProvider } from '~/providers/session-provider';

export function AppProviders({ children }: PropsWithChildren) {
  return (
    <QueryProvider>
      <SessionProvider>
        <RealtimeProvider>{children}</RealtimeProvider>
      </SessionProvider>
    </QueryProvider>
  );
}
