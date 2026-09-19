import { BadRequestException } from '@nestjs/common';
import { PasswordResetService } from './password-reset.service';

describe('PasswordResetService', () => {
  it('generates a recovery link without revealing account existence', async () => {
    const generateLink = jest.fn().mockResolvedValue({ data: { properties: { action_link: 'https://example.com/recovery' } }, error: null });
    const sendSupabasePasswordResetEmail = jest.fn().mockResolvedValue(undefined);
    const service = new PasswordResetService({ getClient: () => ({ auth: { admin: { generateLink } } }) } as never, { sendSupabasePasswordResetEmail } as never);
    process.env.PASSWORD_RESET_URL = 'https://example.com/reset-password';

    await expect(service.request('unknown@example.com')).resolves.toBeUndefined();
    expect(generateLink).toHaveBeenCalledWith(expect.objectContaining({ type: 'recovery', email: 'unknown@example.com' }));
    expect(sendSupabasePasswordResetEmail).toHaveBeenCalledWith('unknown@example.com', 'https://example.com/recovery');
  });

  it('rejects mismatched passwords before touching Supabase Auth', async () => {
    const getUser = jest.fn();
    const service = new PasswordResetService({ getClient: () => ({ auth: { getUser } }) } as never, { sendSupabasePasswordResetEmail: jest.fn() } as never);
    await expect(service.reset('token', 'newPassword1', 'differentPassword1')).rejects.toBeInstanceOf(BadRequestException);
    expect(getUser).not.toHaveBeenCalled();
  });

  it('updates the password using the recovery access token', async () => {
    const getUser = jest.fn().mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null });
    const updateUserById = jest.fn().mockResolvedValue({ error: null });
    const service = new PasswordResetService({ getClient: () => ({ auth: { getUser, admin: { updateUserById } } }) } as never, { sendSupabasePasswordResetEmail: jest.fn() } as never);
    await service.reset('recovery-access-token', 'newPassword1', 'newPassword1');
    expect(getUser).toHaveBeenCalledWith('recovery-access-token');
    expect(updateUserById).toHaveBeenCalledWith('user-1', { password: 'newPassword1' });
  });
});
