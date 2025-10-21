import { env } from '~/config/env';

export interface LoginResponse {
  accessToken: string;
  refreshToken: string;
  user: {
    id: string;
    email: string;
    displayName?: string;
  };
}

export interface RefreshResponse {
  accessToken: string;
  refreshToken?: string;
}

export async function loginWithEmail(email: string, password: string): Promise<LoginResponse> {
  const response = await fetch(`${env.apiUrl}/auth/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email, password }),
  });

  if (!response.ok) {
    const message = await safeReadError(response);
    throw new Error(message ?? 'Unable to sign in with provided credentials.');
  }

  return response.json() as Promise<LoginResponse>;
}

export async function refreshSession(refreshToken: string): Promise<RefreshResponse> {
  const response = await fetch(`${env.apiUrl}/auth/refresh`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ refreshToken }),
  });

  if (!response.ok) {
    const message = await safeReadError(response);
    throw new Error(message ?? 'Unable to refresh session.');
  }

  return response.json() as Promise<RefreshResponse>;
}

export async function revokeSession(token: string) {
  try {
    await fetch(`${env.apiUrl}/auth/logout`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
      },
    });
  } catch (error) {
    console.warn('[auth-service] Failed to revoke session', error);
  }
}

async function safeReadError(response: Response) {
  try {
    const value = await response.json();
    if (typeof value?.message === 'string') {
      return value.message;
    }
  } catch {
    // ignore parse issues
  }
  return undefined;
}
