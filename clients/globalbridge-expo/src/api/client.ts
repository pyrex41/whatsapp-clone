import { z } from 'zod';

import { env } from '~/config/env';
import { useSessionStore } from '~/state/session-store';

type QueryValue = string | number | boolean | null | undefined;

export interface ApiClientOptions {
  baseUrl?: string;
  getAccessToken?: () => string | null;
  onUnauthorized?: () => void;
  onTokenRefresh?: () => Promise<void>;
  fetchImpl?: typeof fetch;
}

export interface RequestOptions<T> {
  path: string;
  method?: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
  query?: Record<string, QueryValue | QueryValue[]>;
  body?: unknown;
  headers?: Record<string, string>;
  schema?: z.ZodType<T>;
  signal?: AbortSignal;
}

export class ApiError extends Error {
  status: number;
  body?: unknown;

  constructor(status: number, message: string, body?: unknown) {
    super(message);
    this.status = status;
    this.body = body;
  }
}

export class ApiClient {
  private readonly baseUrl: string;
  private readonly getAccessToken?: () => string | null;
  private readonly onUnauthorized?: () => void;
  private readonly onTokenRefresh?: () => Promise<void>;
  private readonly fetchImpl: typeof fetch;

  constructor(options: ApiClientOptions = {}) {
    this.baseUrl = options.baseUrl ?? env.apiUrl;
    this.getAccessToken = options.getAccessToken;
    this.onUnauthorized = options.onUnauthorized;
    this.onTokenRefresh = options.onTokenRefresh;
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  async request<T>(options: RequestOptions<T>): Promise<T> {
    const url = this.buildUrl(options.path, options.query);
    const headers = new Headers({ Accept: 'application/json', ...(options.headers ?? {}) });

    const accessToken = this.getAccessToken?.();
    if (accessToken) {
      headers.set('Authorization', `Bearer ${accessToken}`);
    }

    let body: string | undefined;
    if (options.body !== undefined) {
      headers.set('Content-Type', 'application/json');
      body = JSON.stringify(options.body);
    }

    let response = await this.fetchImpl(url, {
      method: options.method ?? 'GET',
      headers,
      body,
      signal: options.signal,
    });

    // If we get a 401 and have a token refresh callback, try refreshing once
    if (response.status === 401 && this.onTokenRefresh) {
      try {
        await this.onTokenRefresh();

        // Retry the request with the new token
        const newAccessToken = this.getAccessToken?.();
        if (newAccessToken && newAccessToken !== accessToken) {
          const newHeaders = new Headers({ Accept: 'application/json', ...(options.headers ?? {}) });
          newHeaders.set('Authorization', `Bearer ${newAccessToken}`);

          response = await this.fetchImpl(url, {
            method: options.method ?? 'GET',
            headers: newHeaders,
            body,
            signal: options.signal,
          });
        }
      } catch (refreshError) {
        // If refresh fails, fall through to unauthorized handling
        console.warn('[ApiClient] Token refresh failed:', refreshError);
      }
    }

    if (response.status === 401) {
      this.onUnauthorized?.();
    }

    const payload = await this.readResponseBody(response);

    if (!response.ok) {
      const message = this.extractErrorMessage(payload) ?? `Request failed with status ${response.status}`;
      throw new ApiError(response.status, message, payload);
    }

    if (!options.schema) {
      return payload as T;
    }

    return options.schema.parse(payload);
  }

  private buildUrl(path: string, query?: Record<string, QueryValue | QueryValue[]>) {
    const url = new URL(path, this.baseUrl);
    if (query) {
      Object.entries(query).forEach(([key, value]) => {
        if (value === undefined || value === null) return;
        if (Array.isArray(value)) {
          value.forEach((entry) => {
            if (entry === undefined || entry === null) return;
            url.searchParams.append(key, String(entry));
          });
        } else {
          url.searchParams.set(key, String(value));
        }
      });
    }
    return url.toString();
  }

  private async readResponseBody(response: Response): Promise<unknown> {
    const contentType = response.headers.get('content-type');
    if (contentType?.includes('application/json')) {
      try {
        return await response.json();
      } catch {
        return null;
      }
    }
    return null;
  }

  private extractErrorMessage(payload: unknown) {
    if (typeof payload === 'string') {
      return payload;
    }
    if (payload && typeof payload === 'object') {
      const maybeMessage = (payload as { message?: string }).message;
      if (typeof maybeMessage === 'string') {
        return maybeMessage;
      }
      if ('error' in (payload as Record<string, unknown>)) {
        const maybeError = (payload as { error?: string }).error;
        if (typeof maybeError === 'string') {
          return maybeError;
        }
      }
    }
    return undefined;
  }
}

export const apiClient = new ApiClient({
  getAccessToken: () => useSessionStore.getState().tokens?.accessToken ?? null,
  onTokenRefresh: async () => {
    await useSessionStore.getState().refresh();
  },
  onUnauthorized: () => {
    const { logout, status } = useSessionStore.getState();
    if (status !== 'unauthenticated') {
      void logout();
    }
  },
});
