import { UnauthorizedException } from '@nestjs/common';
import { RefreshTokenService } from './refresh-token.service';

function makeClient(rpcResult: unknown) {
  const rpc = jest.fn().mockResolvedValue(rpcResult);
  const insert = jest.fn().mockResolvedValue({ error: null });
  const updateChain = { update: jest.fn(() => updateChain), eq: jest.fn(() => updateChain), is: jest.fn().mockResolvedValue({ error: null }) };
  return { client: { rpc, from: jest.fn(() => ({ insert, ...updateChain })) }, rpc, insert };
}

describe('RefreshTokenService', () => {
  it('issues a high-entropy refresh token and stores only its hash', async () => {
    const { client, insert } = makeClient({ data: null, error: null });
    const service = new RefreshTokenService({ getClient: () => client } as never);

    const token = await service.issue('user-1');

    expect(token.length).toBeGreaterThan(50);
    expect(insert).toHaveBeenCalledWith(expect.objectContaining({ usuario_id: 'user-1', token_hash: expect.stringMatching(/^[a-f0-9]{64}$/) }));
    expect(insert.mock.calls[0][0].token_hash).not.toBe(token);
  });

  it('rotates a valid refresh token', async () => {
    const { client, rpc } = makeClient({ data: [{ user_id: 'user-1', new_token_id: 'new-1', replay_detected: false }], error: null });
    const service = new RefreshTokenService({ getClient: () => client } as never);

    const result = await service.rotate('old-token');

    expect(result.userId).toBe('user-1');
    expect(result.refreshToken.length).toBeGreaterThan(50);
    expect(rpc).toHaveBeenCalledWith('rotate_refresh_token', expect.objectContaining({ p_token_hash: expect.stringMatching(/^[a-f0-9]{64}$/) }));
  });

  it('rejects replayed or invalid refresh tokens', async () => {
    const { client } = makeClient({ data: [{ user_id: 'user-1', new_token_id: null, replay_detected: true }], error: null });
    const service = new RefreshTokenService({ getClient: () => client } as never);

    await expect(service.rotate('replayed-token')).rejects.toBeInstanceOf(UnauthorizedException);
  });
});
