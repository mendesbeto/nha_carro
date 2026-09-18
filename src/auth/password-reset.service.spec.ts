import { BadRequestException } from '@nestjs/common';
import { PasswordResetService } from './password-reset.service';
import * as bcrypt from 'bcrypt';

jest.mock('bcrypt', () => ({ hash: jest.fn().mockResolvedValue('new-password-hash') }));

describe('PasswordResetService', () => {
  it('does not reveal whether an email exists when requesting reset', async () => {
    const maybeSingle = jest.fn().mockResolvedValue({ data: null, error: null });
    const client = { from: jest.fn(() => ({ select: jest.fn(() => ({ eq: jest.fn(() => ({ maybeSingle })) })) })) };
    const emailService = { sendPasswordResetEmail: jest.fn() };
    const refresh = { revokeAll: jest.fn() };
    const service = new PasswordResetService({ getClient: () => client } as never, refresh as never, emailService as never);

    await expect(service.request('unknown@example.com')).resolves.toBeUndefined();
    expect(emailService.sendPasswordResetEmail).not.toHaveBeenCalled();
  });

  it('rejects mismatched passwords before consuming a reset token', async () => {
    const rpc = jest.fn();
    const service = new PasswordResetService({ getClient: () => ({ rpc }) } as never, { revokeAll: jest.fn() } as never, { sendPasswordResetEmail: jest.fn() } as never);

    await expect(service.reset('token', 'newPassword1', 'differentPassword1'))
      .rejects.toBeInstanceOf(BadRequestException);
    expect(rpc).not.toHaveBeenCalled();
  });

  it('atomically completes reset and revokes existing refresh sessions', async () => {
    const rpc = jest.fn().mockResolvedValue({ data: [{ user_id: 'user-1' }], error: null });
    const refresh = { revokeAll: jest.fn().mockResolvedValue(undefined) };
    const service = new PasswordResetService({ getClient: () => ({ rpc }) } as never, refresh as never, { sendPasswordResetEmail: jest.fn() } as never);

    await service.reset('one-time-token', 'newPassword1', 'newPassword1');

    expect(bcrypt.hash).toHaveBeenCalledWith('newPassword1', 12);
    expect(rpc).toHaveBeenCalledWith('complete_password_reset', expect.objectContaining({ p_token_hash: expect.stringMatching(/^[a-f0-9]{64}$/), p_password_hash: 'new-password-hash' }));
    expect(refresh.revokeAll).toHaveBeenCalledWith('user-1');
  });
});
