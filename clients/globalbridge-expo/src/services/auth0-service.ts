import * as AuthSession from 'expo-auth-session';
import * as WebBrowser from 'expo-web-browser';

import { env } from '~/config/env';

WebBrowser.maybeCompleteAuthSession();

export interface Auth0LoginResult {
  accessToken: string;
  refreshToken?: string;
  idToken?: string;
  user?: {
    id: string;
    email?: string;
    displayName?: string;
  };
}

export interface Auth0RefreshResult {
  accessToken: string;
  refreshToken?: string;
  idToken?: string;
}

function ensureConfig() {
  if (!env.auth0Domain || !env.auth0ClientId) {
    throw new Error('Missing Auth0 configuration. Set EXPO_PUBLIC_AUTH0_DOMAIN and EXPO_PUBLIC_AUTH0_CLIENT_ID.');
  }
}

function getRedirectUri() {
  // expo-router sets a scheme in app.config.ts (scheme: 'globalbridge')
  // Use that for native, and AuthSession will derive web redirect as needed
  return AuthSession.makeRedirectUri({ useProxy: false, preferLocalhost: true, scheme: 'globalbridge' });
}

function decodeJwtPayload(token: string | undefined): Record<string, unknown> | null {
  if (!token) return null;
  const parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    // atob may not be available in all RN environments; fall back to userinfo
    if (typeof atob !== 'function') return null;
    const json = atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'));
    return JSON.parse(json) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export async function auth0Login(): Promise<Auth0LoginResult> {
  ensureConfig();

  const discovery: AuthSession.DiscoveryDocument = {
    authorizationEndpoint: `https://${env.auth0Domain}/authorize`,
    tokenEndpoint: `https://${env.auth0Domain}/oauth/token`,
    revocationEndpoint: `https://${env.auth0Domain}/oauth/revoke`,
    userInfoEndpoint: `https://${env.auth0Domain}/userinfo`,
  };

  const redirectUri = getRedirectUri();

  const request = new AuthSession.AuthRequest({
    clientId: env.auth0ClientId!,
    redirectUri,
    responseType: AuthSession.ResponseType.Code,
    scopes: ['openid', 'profile', 'email', 'offline_access'],
    extraParams: env.auth0Audience ? { audience: env.auth0Audience } : undefined,
    usePKCE: true,
  });

  await request.makeAuthUrlAsync(discovery);
  const result = await request.promptAsync(discovery, { useProxy: false });

  if (result.type !== 'success' || !result.params.code) {
    throw new Error('Authentication was cancelled or failed.');
  }

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: env.auth0ClientId!,
    code_verifier: request.codeVerifier!,
    code: result.params.code,
    redirect_uri: redirectUri,
  });

  const tokenResponse = await fetch(discovery.tokenEndpoint!, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });

  if (!tokenResponse.ok) {
    let message = 'Failed to exchange authorization code.';
    try {
      const json = await tokenResponse.json();
      if (typeof json?.error_description === 'string') message = json.error_description;
      else if (typeof json?.error === 'string') message = json.error;
    } catch {}
    throw new Error(message);
  }

  const tokens = (await tokenResponse.json()) as {
    access_token: string;
    id_token?: string;
    refresh_token?: string;
    expires_in?: number;
    token_type?: string;
  };

  // Best-effort user extraction
  let user: Auth0LoginResult['user'] | undefined;
  const idClaims = decodeJwtPayload(tokens.id_token);
  if (idClaims) {
    user = {
      id: String(idClaims.sub ?? ''),
      email: typeof idClaims.email === 'string' ? idClaims.email : undefined,
      displayName: (idClaims.name ?? idClaims.nickname ?? idClaims.preferred_username) as string | undefined,
    };
  } else {
    // Try userinfo endpoint as fallback
    try {
      const userInfo = await fetch(discovery.userInfoEndpoint!, {
        headers: { Authorization: `Bearer ${tokens.access_token}` },
      }).then((r) => r.json());
      user = {
        id: String(userInfo.sub ?? ''),
        email: typeof userInfo.email === 'string' ? userInfo.email : undefined,
        displayName: (userInfo.name ?? userInfo.nickname ?? userInfo.preferred_username) as string | undefined,
      };
    } catch {}
  }

  return {
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token,
    idToken: tokens.id_token,
    user,
  };
}

export async function auth0Refresh(refreshToken: string): Promise<Auth0RefreshResult> {
  ensureConfig();
  const discovery: AuthSession.DiscoveryDocument = {
    tokenEndpoint: `https://${env.auth0Domain}/oauth/token`,
  };

  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    client_id: env.auth0ClientId!,
    refresh_token: refreshToken,
  });

  const response = await fetch(discovery.tokenEndpoint!, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });

  if (!response.ok) {
    throw new Error('Failed to refresh session.');
  }

  const tokens = (await response.json()) as {
    access_token: string;
    id_token?: string;
    refresh_token?: string;
  };

  return {
    accessToken: tokens.access_token,
    idToken: tokens.id_token,
    refreshToken: tokens.refresh_token,
  };
}

export async function auth0Revoke(accessToken: string | null | undefined) {
  if (!accessToken) return;
  ensureConfig();
  try {
    await fetch(`https://${env.auth0Domain}/oauth/revoke`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ token: accessToken, client_id: env.auth0ClientId! }).toString(),
    });
  } catch (e) {
    // best effort; ignore
  }
}
