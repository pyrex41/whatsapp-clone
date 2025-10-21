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

async function readError(response: Response) {
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

async function handle<T>(response: Response, fallbackMessage: string): Promise<T> {
  if (!response.ok) {
    const message = await readError(response);
    throw new Error(message ?? fallbackMessage);
  }
  return (await response.json()) as T;
}

export async function loginWithEmail(email: string, password: string): Promise<LoginResponse> {
  const response = await fetch(`${env.apiUrl}/auth/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    // Backend expects 'identifier' field instead of 'email'
    body: JSON.stringify({ identifier: email, password }),
  });

  return handle<LoginResponse>(response, 'Unable to sign in with provided credentials.');
}

export async function refreshSession(refreshToken: string): Promise<RefreshResponse> {
  const response = await fetch(`${env.apiUrl}/auth/refresh`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ refreshToken }),
  });

  return handle<RefreshResponse>(response, 'Unable to refresh session.');
}

export async function revokeSession(accessToken: string) {
  try {
    await fetch(`${env.apiUrl}/auth/logout`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    });
  } catch (error) {
    console.warn('[auth-service] Failed to revoke session', error);
  }
}
