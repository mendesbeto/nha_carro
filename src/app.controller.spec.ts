import { ServiceUnavailableException } from '@nestjs/common';
import { AppController } from './app.controller';

describe('AppController', () => {
  const makeController = (configured: boolean, error: unknown = null) =>
    new AppController({
      isConfigured: () => configured,
      getClient: () => ({
        from: () => ({
          select: () => ({
            limit: async () => ({ error }),
          }),
        }),
      }),
    } as never);

  it('returns liveness status without requiring Supabase connectivity', () => {
    expect(makeController(false).health()).toEqual({
      status: 'ok',
      supabaseConfigured: false,
    });
  });

  it('reports readiness when Supabase responds successfully', async () => {
    await expect(makeController(true).readiness()).resolves.toEqual({
      status: 'ready',
      supabase: 'ok',
    });
  });

  it('fails readiness when Supabase is not configured', async () => {
    await expect(makeController(false).readiness()).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('fails readiness when Supabase query returns an error', async () => {
    await expect(
      makeController(true, new Error('connection failed')).readiness(),
    ).rejects.toBeInstanceOf(ServiceUnavailableException);
  });
});
