import { PropsWithChildren, useEffect, useState } from 'react';
import { AppState, AppStateStatus } from 'react-native';
import { QueryClient, QueryClientProvider, focusManager } from '@tanstack/react-query';

function subscribeToAppState(callback: (isFocused: boolean) => void) {
  const handleChange = (state: AppStateStatus) => {
    callback(state === 'active');
  };

  const subscription = AppState.addEventListener('change', handleChange);

  return () => {
    subscription.remove();
  };
}

export function QueryProvider({ children }: PropsWithChildren) {
  const [client] = useState(() => new QueryClient({
    defaultOptions: {
      queries: {
        staleTime: 30_000,
        gcTime: 5 * 60_000,
        retry: (failureCount, error) => {
          if (error instanceof Error && 'status' in error) {
            const status = (error as { status?: number }).status;
            if (status && status >= 400 && status < 500 && status !== 429) {
              return false;
            }
          }
          return failureCount < 3;
        },
        refetchOnMount: 'always',
        refetchOnReconnect: true,
        refetchOnWindowFocus: true,
      },
      mutations: {
        retry: 1,
      },
    },
  }));

  useEffect(() => {
    const unsubscribe = subscribeToAppState((isFocused) => {
      focusManager.setFocused(isFocused);
    });
    return unsubscribe;
  }, []);

  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}
