import { ExecutionContext, UnauthorizedException } from '@nestjs/common';
import { JwtAuthGuard } from './jwt-auth.guard';

describe('JwtAuthGuard', () => {
  function context(authorization?: string): ExecutionContext {
    const request = { headers: { authorization } } as any;
    return { switchToHttp: () => ({ getRequest: () => request }) } as ExecutionContext;
  }

  it('rejects requests without a Bearer token', async () => {
    const guard = new JwtAuthGuard({ verifyAsync: jest.fn() } as never, {} as never);
    await expect(guard.canActivate(context())).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a token when the server-side session version changed', async () => {
    const verifyAsync = jest.fn().mockResolvedValue({ sub: 'user-1', email: 'beto@example.com', role: 'passenger', sv: 0 });
    const from = jest.fn(() => ({
      select: jest.fn(() => ({ eq: jest.fn(() => ({ maybeSingle: jest.fn().mockResolvedValue({ data: { id: 'user-1', tipo_perfil: 'PASSAGEIRO', status_conta: 'ATIVO', session_version: 1 }, error: null }) })) })),
    }));
    const guard = new JwtAuthGuard({ verifyAsync } as never, { getClient: () => ({ from }) } as never);

    await expect(guard.canActivate(context('Bearer token'))).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('accepts a valid token and refreshes the role from the database', async () => {
    const requestContext = context('Bearer token');
    const request = (requestContext as any).switchToHttp().getRequest();
    const verifyAsync = jest.fn().mockResolvedValue({ sub: 'user-1', email: 'beto@example.com', role: 'passenger', sv: 2 });
    const from = jest.fn(() => ({
      select: jest.fn(() => ({ eq: jest.fn(() => ({ maybeSingle: jest.fn().mockResolvedValue({ data: { id: 'user-1', tipo_perfil: 'MOTORISTA', status_conta: 'ATIVO', session_version: 2 }, error: null }) })) })),
    }));
    const guard = new JwtAuthGuard({ verifyAsync } as never, { getClient: () => ({ from }) } as never);

    await expect(guard.canActivate(requestContext)).resolves.toBe(true);
    expect(request.user).toMatchObject({ sub: 'user-1', role: 'driver', sv: 2 });
  });
});
