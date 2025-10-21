import { describe, expect, it, vi } from 'vitest';
import { z } from 'zod';

import { ApiClient, ApiError } from '~/api/client';

const ExampleSchema = z.object({ greeting: z.string() });

describe('ApiClient', () => {
  it('sends JSON requests with authorization header', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ greeting: 'hi' }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    );

    const client = new ApiClient({
      baseUrl: 'https://example.test/api',
      getAccessToken: () => 'token-123',
      fetchImpl: fetchMock,
    });

    const result = await client.request({
      path: '/hello',
      method: 'POST',
      body: { name: 'Ada' },
      schema: ExampleSchema,
    });

    expect(result.greeting).toBe('hi');
    expect(fetchMock).toHaveBeenCalledWith('https://example.test/hello', expect.any(Object));
    const options = fetchMock.mock.calls[0][1]!;
    expect(options?.method).toBe('POST');
    expect(options?.headers?.get('authorization')).toBe('Bearer token-123');
    expect(options?.headers?.get('content-type')).toBe('application/json');
    expect(options?.body).toBe(JSON.stringify({ name: 'Ada' }));
  });

  it('throws ApiError on non-ok responses', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: 'bad_request' }), {
        status: 400,
        headers: { 'content-type': 'application/json' },
      }),
    );

    const client = new ApiClient({ baseUrl: 'https://example.test', fetchImpl: fetchMock });

    await expect(
      client.request({
        path: '/hello',
        schema: ExampleSchema,
      }),
    ).rejects.toMatchObject({ status: 400, message: 'bad_request' } satisfies Partial<ApiError>);
  });

  it('supports query parameters', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ greeting: 'world' }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    );

    const client = new ApiClient({ baseUrl: 'https://example.test', fetchImpl: fetchMock });

    await client.request({
      path: '/threads',
      query: { limit: 10, include_archived: true, tags: ['a', 'b'] },
      schema: ExampleSchema,
    });

    const url = new URL(fetchMock.mock.calls[0][0] as string);
    expect(url.searchParams.get('limit')).toBe('10');
    expect(url.searchParams.get('include_archived')).toBe('true');
    expect(url.searchParams.getAll('tags')).toEqual(['a', 'b']);
  });
});
