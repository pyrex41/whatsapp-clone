import { AppState } from 'react-native';
import type { AppStateStatus } from 'react-native';
import { create } from 'zustand';
import * as LocalAuthentication from 'expo-local-authentication';

import { deleteSecureItem, getSecureItem, setSecureItem } from '~/lib/secure-store';
import { generateSalt, hashPin } from '~/lib/crypto';
import { loginWithEmail, refreshSession, revokeSession } from '~/services/auth-service';
import { auth0Login, auth0Refresh, auth0Revoke } from '~/services/auth0-service';
import { env } from '~/config/env';

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
  provider?: 'auth0' | 'legacy';
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
  loadSession: () => void;
  login: (email: string, password: string) => Promise<void>;
  loginWithAuth0: () => Promise<void>;
  logout: () => Promise<void>;
  refresh: () => Promise<void>;
  lock: () => void;
  unlockWithBiometrics: () => Promise<boolean>;
  unlockWithPin: (pin: string) => Promise<boolean>;
  setPin: (pin: string) => Promise<void>;
  clearError: () => void;
  toggleBiometrics: (enabled: boolean) => Promise<void>;
}

let appStateSubscription: ReturnType<typeof AppState.addEventListener> | null = null;

function ensureAppStateListener(lock: () => void) {
  if (appStateSubscription) return;
  appStateSubscription = AppState.addEventListener('change', (status: AppStateStatus) => {
    if (status !== 'active') {
      lock();
    }
  });
}

function removeAppStateListener() {
  appStateSubscription?.remove();
  appStateSubscription = null;
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
  const stored = await getSecureItem<SessionPreferences>(STORAGE_KEYS.preferences);
  return stored ?? { biometricsEnabled: false };
}

async function writePreferences(preferences: SessionPreferences) {
  await setSecureItem(STORAGE_KEYS.preferences, preferences);
}

export const useSessionStore = create<SessionState>((set, get) => ({
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

    ensureAppStateListener(() => get().lock());

    const hasPin = Boolean(storedPin);
    const biometricsEnabled = Boolean(storedPreferences.biometricsEnabled);
    const shouldLock = Boolean(storedTokens && (hasPin || biometricsEnabled));

    set({
      tokens: storedTokens,
      status: storedTokens ? (shouldLock ? 'locked' : 'authenticated') : 'unauthenticated',
      hydrated: true,
      biometricsSupported: biometricHardware,
      preferences: storedPreferences,
      pinConfigured: hasPin,
    });
  },
  loginWithAuth0: async () => {
    set({ status: 'authenticating', error: undefined });
    try {
      const result = await auth0Login();
      const record: SessionTokens = {
        accessToken: result.accessToken,
        refreshToken: result.refreshToken ?? '',
        user: result.user ?? { id: 'auth0-user', email: '' },
        fetchedAt: Date.now(),
        provider: 'auth0',
      };
      await setSecureItem(STORAGE_KEYS.session, record);
      ensureAppStateListener(() => get().lock());
      set({ tokens: record, status: 'authenticated', error: undefined, hydrated: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to sign in.';
      set({ status: 'unauthenticated', error: message });
      throw error;
    }
  },
  login: async (email, password) => {
    set({ status: 'authenticating', error: undefined });
    try {
      // If Auth0 is configured, prefer Auth0 login flow regardless of email/password
      if (env.auth0Domain && env.auth0ClientId) {
        const result = await auth0Login();
        const record: SessionTokens = {
          accessToken: result.accessToken,
          refreshToken: result.refreshToken ?? '',
          user: result.user ?? { id: 'auth0-user', email: '' },
          fetchedAt: Date.now(),
          provider: 'auth0',
        };
        await setSecureItem(STORAGE_KEYS.session, record);
        ensureAppStateListener(() => get().lock());
        set({ tokens: record, status: 'authenticated', error: undefined, hydrated: true });
        return;
      }

      const result = await loginWithEmail(email, password);
      const record: SessionTokens = {
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        user: result.user,
        fetchedAt: Date.now(),
        provider: 'legacy',
      };
      await setSecureItem(STORAGE_KEYS.session, record);
      ensureAppStateListener(() => get().lock());
      set({
        tokens: record,
        status: 'authenticated',
        error: undefined,
        hydrated: true,
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
      if (tokens.provider === 'auth0' || (env.auth0Domain && env.auth0ClientId)) {
        await auth0Revoke(tokens.accessToken);
      } else {
        await revokeSession(tokens.accessToken);
      }
    }
    await deleteSecureItem(STORAGE_KEYS.session);
    removeAppStateListener();
    const pinRecord = await readPinRecord();
    set({
      status: 'unauthenticated',
      tokens: null,
      pinConfigured: Boolean(pinRecord),
    });
  },
  refresh: async () => {
    const tokens = get().tokens;
    if (!tokens) return;
    try {
      let nextAccessToken = tokens.accessToken;
      let nextRefreshToken: string | undefined = tokens.refreshToken;

      if (tokens.provider === 'auth0' || (env.auth0Domain && env.auth0ClientId)) {
        const refreshed = await auth0Refresh(tokens.refreshToken);
        nextAccessToken = refreshed.accessToken;
        nextRefreshToken = refreshed.refreshToken ?? tokens.refreshToken;
      } else {
        const refreshed = await refreshSession(tokens.refreshToken);
        nextAccessToken = refreshed.accessToken;
        nextRefreshToken = refreshed.refreshToken ?? tokens.refreshToken;
      }

      const nextRecord: SessionTokens = {
        accessToken: nextAccessToken,
        refreshToken: nextRefreshToken ?? tokens.refreshToken,
        user: tokens.user,
        fetchedAt: Date.now(),
        provider: tokens.provider,
      };
      await setSecureItem(STORAGE_KEYS.session, nextRecord);
      set({ tokens: nextRecord });
    } catch (error) {
      console.warn('[session-store] Refresh failed', error);
      await get().logout();
    }
  },
  lock: () => {
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
    const supported = get().biometricsSupported;
    if (enabled && supported === false) {
      set({ preferences: { ...get().preferences, biometricsEnabled: false } });
      return;
    }
    const next = { ...get().preferences, biometricsEnabled: enabled };
    await writePreferences(next);
    set({ preferences: next });
  },
}));
