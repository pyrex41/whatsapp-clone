import Constants from 'expo-constants';

type ExtraConfig = {
  apiUrl?: string;
  auth0Domain?: string;
  auth0ClientId?: string;
  auth0Audience?: string;
  eas?: {
    projectId?: string;
  };
};

function readStringEnv(key: string): string | undefined {
  const value = process.env[key];
  return typeof value === 'string' && value.length > 0 ? value : undefined;
}

function resolveExtra(): ExtraConfig {
  const extra = (Constants?.expoConfig?.extra as ExtraConfig | undefined) ?? {};
  return extra;
}

const extra = resolveExtra();
const apiUrl = readStringEnv('EXPO_PUBLIC_API_URL') ?? extra.apiUrl ?? 'http://localhost:4000/api';
const auth0Domain = readStringEnv('EXPO_PUBLIC_AUTH0_DOMAIN') ?? extra.auth0Domain;
const auth0ClientId = readStringEnv('EXPO_PUBLIC_AUTH0_CLIENT_ID') ?? extra.auth0ClientId;
const auth0Audience = readStringEnv('EXPO_PUBLIC_AUTH0_AUDIENCE') ?? extra.auth0Audience;

export const env = {
  apiUrl,
  auth0Domain,
  auth0ClientId,
  auth0Audience,
  easProjectId: extra.eas?.projectId,
  isDevelopment: process.env.NODE_ENV !== 'production',
};
