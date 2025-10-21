import { create } from 'zustand';
import { AppState, AppStateStatus } from 'react-native';
import * as LocalAuthentication from 'expo-local-authentication';

import { deleteSecureItem, getSecureItem, setSecureItem } from '~/lib/secure-store';
import { generateSalt, hashPin } from '~/lib/crypto';
import { loginWithEmail, refreshSession, revokeSession } from '~/services/auth-service';

const STORAGE_KEYS = {
  session: 'gb::session',
  pin: 'gb::pin',
  preferences: 'gb::session-preferences',
} as const;

type SessionStatus = 'unknown' | 'unauthenticated' | 'authenticating' | 'authenticated' | 'locked';

export interface SessionTokens {
  accessToken: string;
  refreshToken: string;
  user: {
    id: string;
    email: string;
    displayName?: string;
  };
  fetchedAt: number;
}

interface PinRecord {
  hash: string;
  salt: string;
}

interface SessionPreferences {
  biometricsEnabled: boolean;
}

interface SessionState {
  status: SessionStatus;
  hydrated: boolean;
  tokens: SessionTokens | null;
  error?: string;
  biometricsSupported: boolean | null;
  preferences: SessionPreferences;
  pinConfigured: boolean;
  loadSession: () => Promise<void>;
  login: (email: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
  lock: () => Promise<void>;
  unlockWithBiometrics: () => Promise<boolean>;
  unlockWithPin: (pin: string) => Promise<boolean>;
  setPin: (pin: string) => Promise<void>;
  clearError: () => void;
  toggleBiometrics: (enabled: boolean) => Promise<void>;
}

async function readPinRecord(): Promise<PinRecord | null> {
  return getSecureItem<PinRecord>(STORAGE_KEYS.pin);
}

async function writePinRecord(pin: string) {
  const salt = await generateSalt();
  const { hash } = await hashPin(pin, salt);
  await setSecureItem(STORAGE_KEYS.pin, { hash, salt });
}

async function matchesPin(candidate: string): Promise<boolean> {
  const record = await readPinRecord();
  if (!record) return false;
  const { hash } = await hashPin(candidate, record.salt);
  return hash === record.hash;
}

async function readPreferences(): Promise<SessionPreferences> {
  const fallback: SessionPreferences = { biometricsEnabled: false };
  const stored = await getSecureItem<SessionPreferences>(STORAGE_KEYS.preferences);
  return stored ?? fallback;
}

async function writePreferences(preferences: SessionPreferences) {
  await setSecureItem(STORAGE_KEYS.preferences, preferences);
}

type InternalState = SessionState;

export const useSessionStore = create<SessionState>((set, get) => {
  let appStateListener: ReturnType<typeof AppState.addEventListener> | null = null;

  const attachAppStateListener = () => {
    if (appStateListener) return;
    appStateListener = AppState.addEventListener('change', (status: AppStateStatus) => {
      if (status !== 'active') {
        void get().lock();
      }
    });
  };

  const cleanup = () => {
    appStateListener?.remove();
    appStateListener = null;
  };

  return {
    status: 'unknown',
    hydrated: false,
    tokens: null,
    biometricsSupported: null,
    preferences: { biometricsEnabled: false },
    pinConfigured: false,
    loadSession: async () => {
      const [storedTokens, storedPin, storedPreferences, biometricHardware] = await Promise.all([
        getSecureItem<SessionTokens>(STORAGE_KEYS.session),
        readPinRecord(),
        readPreferences(),
        LocalAuthentication.hasHardwareAsync().catch(() => false),
      ]);

      attachAppStateListener();

      set({
        tokens: storedTokens,
        status: storedTokens ? 'authenticated' : 'unauthenticated',
        hydrated: true,
        biometricsSupported: biometricHardware,
        preferences: storedPreferences,
        pinConfigured: Boolean(storedPin),
      });
    },
    login: async (email, password) => {
      set({ status: 'authenticating', error: undefined });
      try {
        const result = await loginWithEmail(email, password);
        const record: SessionTokens = {
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
          user: result.user,
          fetchedAt: Date.now(),
        };
        await setSecureItem(STORAGE_KEYS.session, record);
        set({
          tokens: record,
          status: 'authenticated',
          error: undefined,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Unable to sign in.';
        set({
          status: 'unauthenticated',
          error: message,
        });
        throw error;
      }
    },
    logout: async () => {
      const tokens = get().tokens;
      if (tokens) {
        await revokeSession(tokens.accessToken);
      }
      await deleteSecureItem(STORAGE_KEYS.session);
      cleanup();
      set({
        status: 'unauthenticated',
        tokens: null,
      });
    },
    refresh: async () => {
      const tokens = get().tokens;
      if (!tokens) return;
      try {
        const refreshed = await refreshSession(tokens.refreshToken);
        const nextRecord: SessionTokens = {
          accessToken: refreshed.accessToken,
          refreshToken: refreshed.refreshToken ?? tokens.refreshToken,
          user: tokens.user,
          fetchedAt: Date.now(),
        };
        await setSecureItem(STORAGE_KEYS.session, nextRecord);
        set({ tokens: nextRecord });
      } catch (error) {
        console.warn('[session-store] Refresh failed', error);
        await get().logout();
      }
    },
    lock: async () => {
      if (!get().tokens) {
        set({ status: 'unauthenticated' });
        return;
      }
      set({ status: 'locked' });
    },
    unlockWithBiometrics: async () => {
      const { tokens, preferences, biometricsSupported } = get();
      if (!tokens || !preferences.biometricsEnabled || !biometricsSupported) return false;

      const result = await LocalAuthentication.authenticateAsync({
        promptMessage: 'Unlock GlobalBridge',
        fallbackLabel: 'Use passcode',
        disableDeviceFallback: false,
      });

      if (result.success) {
        set({ status: 'authenticated' });
      }

      return result.success;
    },
    unlockWithPin: async (pin: string) => {
      const ok = await matchesPin(pin);
      if (ok) {
        set({ status: 'authenticated' });
      }
      return ok;
    },
    setPin: async (pin: string) => {
      await writePinRecord(pin);
      set({ pinConfigured: true });
    },
    clearError: () => set({ error: undefined }),
    toggleBiometrics: async (enabled: boolean) => {
      const next = { ...get().preferences, biometricsEnabled: enabled };
      await writePreferences(next);
      set({ preferences: next });
    },
  };
});
