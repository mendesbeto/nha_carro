import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { AuthService } from './auth.service';
import * as bcrypt from 'bcrypt';

jest.mock('bcrypt', () => ({
  hash: jest.fn().mockResolvedValue('hashed-password'),
  compare: jest.fn(),
}));

type Chain = {
  select: jest.Mock;
  eq: jest.Mock;
  maybeSingle: jest.Mock;
  insert: jest.Mock;
  single: jest.Mock;
  delete: jest.Mock;
};

function chain(result: unknown): Chain {
  const c = {} as Chain;
  c.select = jest.fn(() => c);
  c.eq = jest.fn(() => c);
  c.maybeSingle = jest.fn().mockResolvedValue(result);
  c.insert = jest.fn(() => c);
  c.single = jest.fn().mockResolvedValue(result);
  c.delete = jest.fn(() => c);
  return c;
}

describe('AuthService', () => {
  const jwtService = { signAsync: jest.fn().mockResolvedValue('access-token') };
  const refreshTokenService = { issue: jest.fn().mockResolvedValue('refresh-token') };
  let supabase: { getClient: jest.Mock };
  let auth: AuthService;

  beforeEach(() => {
    jest.clearAllMocks();
    supabase = { getClient: jest.fn() };
    auth = new AuthService(supabase as never, jwtService as never, refreshTokenService as never);
  });

  it('registers a passenger, normalizes email, hashes the password and issues tokens', async () => {
    const credentials = chain({ data: null, error: null });
    const user = chain({
      data: {
        id: 'user-1', nome: ' Beto ', telefone: 'beto@example.com',
        tipo_perfil: 'PASSAGEIRO', session_version: 0,
      },
      error: null,
    });
    const client = { from: jest.fn((table: string) => table === 'auth_credentials' ? credentials : user) };
    credentials.insert.mockResolvedValue({ error: null });
    supabase.getClient.mockReturnValue(client);

    const result = await auth.register({
      name: ' Beto ', email: ' Beto@Example.COM ', password: 'secret123', role: 'passenger',
    });

    expect(result).toMatchObject({ id: 'user-1', name: 'Beto', email: 'beto@example.com', role: 'passenger' });
    expect(bcrypt.hash).toHaveBeenCalledWith('secret123', 12);
    expect(refreshTokenService.issue).toHaveBeenCalledWith('user-1');
    expect(jwtService.signAsync).toHaveBeenCalledWith({ sub: 'user-1', email: 'beto@example.com', role: 'passenger', sv: 0 });
  });

  it('rejects registration when the email already exists', async () => {
    const credentials = chain({ data: { usuario_id: 'existing' }, error: null });
    const client = { from: jest.fn(() => credentials) };
    supabase.getClient.mockReturnValue(client);

    await expect(auth.register({
      name: 'Beto', email: 'beto@example.com', password: 'secret123', role: 'passenger',
    })).rejects.toBeInstanceOf(ConflictException);
  });

  it('rejects invalid login credentials', async () => {
    const credentials = chain({ data: { usuario_id: 'user-1', email: 'beto@example.com', password_hash: 'hash' }, error: null });
    const client = { from: jest.fn(() => credentials) };
    supabase.getClient.mockReturnValue(client);
    (bcrypt.compare as jest.Mock).mockResolvedValue(false);

    await expect(auth.login({ email: 'beto@example.com', password: 'wrong' }))
      .rejects.toBeInstanceOf(UnauthorizedException);
  });
});
