import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { JwtAuthGuard } from './jwt-auth.guard';

describe('JwtAuthGuard', () => {
  function context(authorization?: string): ExecutionContext {
    const request = { headers: { authorization } } as any;
    return { switchToHttp: () => ({ getRequest: () => request }) } as ExecutionContext;
  }

  it('rejects requests without a Bearer token', async () => {
    const guard = new JwtAuthGuard({ getAuthClient: jest.fn() } as never);
    await expect(guard.canActivate(context())).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects an invalid Supabase access token', async () => {
    const guard = new JwtAuthGuard({ getAuthClient: () => ({ auth: { getUser: jest.fn().mockResolvedValue({ data: { user: null }, error: { message: 'Invalid token' } }) } }) } as never);
    await expect(guard.canActivate(context('Bearer token'))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('accepts a valid token and loads the current role from the database', async () => {
    const requestContext = context('Bearer token');
    const request = (requestContext as any).switchToHttp().getRequest();
    const from = jest.fn(() => ({ select: jest.fn(() => ({ eq: jest.fn(() => ({ maybeSingle: jest.fn().mockResolvedValue({ data: { id: 'user-1', tipo_perfil: 'MOTORISTA', status_conta: 'ATIVO' }, error: null }) })) })) }));
    const guard = new JwtAuthGuard({ getAuthClient: () => ({ auth: { getUser: jest.fn().mockResolvedValue({ data: { user: { id: 'user-1', email: 'beto@example.com' } }, error: null }) }, from }) } as never);

    await expect(guard.canActivate(requestContext)).resolves.toBe(true);
    expect(request.user).toMatchObject({ sub: 'user-1', email: 'beto@example.com', role: 'driver' });
  });

  it('rejects a blocked account', async () => {
    const guard = new JwtAuthGuard({ getAuthClient: () => ({ auth: { getUser: jest.fn().mockResolvedValue({ data: { user: { id: 'user-1', email: 'beto@example.com' } }, error: null }) }, from: jest.fn(() => ({ select: jest.fn(() => ({ eq: jest.fn(() => ({ maybeSingle: jest.fn().mockResolvedValue({ data: { id: 'user-1', tipo_perfil: 'PASSAGEIRO', status_conta: 'BLOQUEADO' }, error: null }) })) })) })) }) } as never);
    await expect(guard.canActivate(context('Bearer token'))).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
