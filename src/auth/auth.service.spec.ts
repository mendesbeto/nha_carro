import { ConflictException, InternalServerErrorException, UnauthorizedException } from '@nestjs/common';
import { AuthService } from './auth.service';

function makeChain(result: unknown) {
  const c: any = {};
  c.select = jest.fn(() => c);
  c.eq = jest.fn(() => c);
  c.maybeSingle = jest.fn().mockResolvedValue(result);
  c.insert = jest.fn(() => c);
  c.single = jest.fn().mockResolvedValue(result);
  return c;
}

describe('AuthService', () => {
  let supabase: { getClient: jest.Mock; getAuthClient: jest.Mock };
  let auth: AuthService;

  beforeEach(() => {
    jest.clearAllMocks();
    supabase = { getClient: jest.fn(), getAuthClient: jest.fn() };
    auth = new AuthService(supabase as never);
  });

  it('registers a passenger through Supabase Auth and returns a session', async () => {
    const profile = makeChain({ data: { id: 'user-1', nome: 'Beto', telefone: '+2459000000', tipo_perfil: 'PASSAGEIRO' }, error: null });
    const adminClient: any = {
      auth: {
        admin: { createUser: jest.fn().mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null }) },
      },
      from: jest.fn(() => profile),
    };
    const authClient: any = {
      auth: {
        signInWithPassword: jest.fn().mockResolvedValue({
          data: { session: { access_token: 'access-token', refresh_token: 'refresh-token' }, user: { id: 'user-1', email: 'beto@example.com' } },
          error: null,
        }),
      },
    };
    supabase.getClient.mockReturnValue(adminClient);
    supabase.getAuthClient.mockReturnValue(authClient);

    const result = await auth.register({ name: ' Beto ', email: ' Beto@Example.COM ', telefone: '+2459000000', password: 'secret123', role: 'passenger' });

    expect(result).toMatchObject({ id: 'user-1', name: 'Beto', email: 'beto@example.com', role: 'passenger', access_token: 'access-token', refresh_token: 'refresh-token' });
    expect(authClient.auth.signInWithPassword).toHaveBeenCalledWith({ email: 'beto@example.com', password: 'secret123' });
  });

  it('rejects registration when the email already exists', async () => {
    const client = { auth: { admin: { createUser: jest.fn().mockResolvedValue({ data: { user: null }, error: { status: 422, message: 'User already registered' } }) } } };
    supabase.getClient.mockReturnValue(client);

    await expect(auth.register({ name: 'Beto', email: 'beto@example.com', telefone: '+2459000000', password: 'secret123', role: 'passenger' })).rejects.toBeInstanceOf(ConflictException);
  });

  it('rejects invalid login credentials', async () => {
    const client = { auth: { signInWithPassword: jest.fn().mockResolvedValue({ data: { user: null, session: null }, error: { message: 'Invalid login credentials' } }) } };
    supabase.getAuthClient.mockReturnValue(client);

    await expect(auth.login({ email: 'beto@example.com', password: 'wrongpass' })).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects a blocked account after authentication', async () => {
    const profile = makeChain({ data: { id: 'user-1', nome: 'Beto', telefone: '+2459000000', tipo_perfil: 'PASSAGEIRO', status_conta: 'BLOQUEADO' }, error: null });
    const signOut = jest.fn().mockResolvedValue({ error: null });
    const authClient: any = {
      auth: {
        signInWithPassword: jest.fn().mockResolvedValue({ data: { user: { id: 'user-1', email: 'beto@example.com' }, session: { access_token: 'access-token', refresh_token: 'refresh-token' } }, error: null }),
      },
      from: jest.fn(() => profile),
    };
    supabase.getAuthClient.mockReturnValue(authClient);
    supabase.getClient.mockReturnValue({ auth: { admin: { signOut } } });

    await expect(auth.login({ email: 'beto@example.com', password: 'secret123' })).rejects.toBeInstanceOf(UnauthorizedException);
    expect(signOut).toHaveBeenCalledWith('access-token');
  });

  it('cleans up the Auth user when profile creation fails', async () => {
    const profile = makeChain({ data: null, error: { code: '23505', message: 'duplicate phone' } });
    const deleteUser = jest.fn().mockResolvedValue({ error: null });
    const client: any = {
      auth: { admin: { createUser: jest.fn().mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null }), deleteUser } },
      from: jest.fn(() => profile),
    };
    supabase.getClient.mockReturnValue(client);

    await expect(auth.register({ name: 'Beto', email: 'beto@example.com', telefone: '+2459000000', password: 'secret123', role: 'passenger' })).rejects.toBeInstanceOf(ConflictException);
    expect(deleteUser).toHaveBeenCalledWith('user-1');
  });

  it('maps unexpected registration failure to a server error', async () => {
    const client = { auth: { admin: { createUser: jest.fn().mockResolvedValue({ data: { user: null }, error: { status: 500, message: 'Auth unavailable' } }) } } };
    supabase.getClient.mockReturnValue(client);

    await expect(auth.register({ name: 'Beto', email: 'beto@example.com', telefone: '+2459000000', password: 'secret123', role: 'passenger' })).rejects.toBeInstanceOf(InternalServerErrorException);
  });
});
