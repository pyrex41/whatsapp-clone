import { env } from '~/config/env';

function deriveSocketUrl(apiUrl: string): string {
  try {
    const url = new URL(apiUrl);
    const isSecure = url.protocol === 'https:' || url.protocol === 'wss:';
    url.protocol = isSecure ? 'wss:' : 'ws:';
    url.pathname = '/socket';
    url.search = '';
    url.hash = '';
    return url.toString();
  } catch {
    // Fallback to localhost websocket
    return 'ws://localhost:4000/socket';
  }
}

export const realtimeConfig = {
  socketUrl: deriveSocketUrl(env.apiUrl),
  heartbeatIntervalMs: 30_000,
  reconnect: {
    maxAttempts: 5,
    intervalMs: 5_000,
  },
};
