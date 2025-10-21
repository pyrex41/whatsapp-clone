import { useMemo } from 'react';
import { useStore } from 'zustand';

import { useSessionStore } from '~/state/session-store';

export function useSession<T>(selector: (state: ReturnType<typeof useSessionStore.getState>) => T) {
  return useStore(useSessionStore, selector);
}

export function useSessionStatus() {
  return useSession((state) => ({
    status: state.status,
    hydrated: state.hydrated,
    error: state.error,
  }));
}

export function useSessionActions() {
  return useMemo(
    () => ({
      loadSession: useSessionStore.getState().loadSession,
      login: useSessionStore.getState().login,
      logout: useSessionStore.getState().logout,
      lock: useSessionStore.getState().lock,
      unlockWithBiometrics: useSessionStore.getState().unlockWithBiometrics,
      unlockWithPin: useSessionStore.getState().unlockWithPin,
      setPin: useSessionStore.getState().setPin,
      clearError: useSessionStore.getState().clearError,
      toggleBiometrics: useSessionStore.getState().toggleBiometrics,
    }),
    [],
  );
}
