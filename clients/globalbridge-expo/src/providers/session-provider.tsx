import { PropsWithChildren, useEffect } from 'react';
import { useRouter, useSegments } from 'expo-router';

import { useSession, useSessionActions } from '~/hooks/use-session';

const AUTH_SEGMENT = '(auth)';

export function SessionProvider({ children }: PropsWithChildren) {
  const router = useRouter();
  const segments = useSegments();
  const { loadSession, unlockWithBiometrics } = useSessionActions();
  const { status, hydrated, error } = useSession((state) => ({
    status: state.status,
    hydrated: state.hydrated,
    error: state.error,
  }));
  const pinConfigured = useSession((state) => state.pinConfigured);
  const biometricsEnabled = useSession((state) => state.preferences.biometricsEnabled);

  useEffect(() => {
    void loadSession();
  }, [loadSession]);

  useEffect(() => {
    if (!hydrated) return;
    const inAuthStack = segments[0] === AUTH_SEGMENT;

    if (status === 'authenticated' && inAuthStack) {
      router.replace('/(tabs)');
    } else if (status === 'unauthenticated' && !inAuthStack) {
      router.replace('/(auth)/login');
    } else if (status === 'locked') {
      router.replace('/(auth)/lock');
    }
  }, [hydrated, router, segments, status]);

  useEffect(() => {
    if (status === 'locked' && biometricsEnabled) {
      void unlockWithBiometrics();
    }
  }, [status, biometricsEnabled, unlockWithBiometrics]);

  useEffect(() => {
    if (!error) return;
    console.warn('[session-provider] authentication error', error);
  }, [error]);

  useEffect(() => {
    if (!hydrated || !pinConfigured) return;
    if (status === 'authenticated' && biometricsEnabled) {
      void unlockWithBiometrics();
    }
  }, [hydrated, biometricsEnabled, pinConfigured, status, unlockWithBiometrics]);

  return children;
}
