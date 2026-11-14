import { EmailConfirmationPageController } from './email-confirmation-page.controller';

describe('EmailConfirmationPageController', () => {
  it('confirms only when Supabase returns an email-confirmed user', async () => {
    const getUser = jest.fn().mockResolvedValue({
      data: { user: { email_confirmed_at: '2026-11-14T12:00:00Z' } },
      error: null,
    });
    const controller = new EmailConfirmationPageController({
      getClient: () => ({ auth: { getUser } }),
    } as never);

    await expect(controller.verify('valid-access-token')).resolves.toEqual({ confirmed: true });
    expect(getUser).toHaveBeenCalledWith('valid-access-token');
  });

  it('rejects missing, oversized, invalid, or unconfirmed tokens', async () => {
    const getUser = jest.fn().mockResolvedValue({
      data: { user: { email_confirmed_at: null } },
      error: null,
    });
    const controller = new EmailConfirmationPageController({
      getClient: () => ({ auth: { getUser } }),
    } as never);

    await expect(controller.verify()).resolves.toEqual({ confirmed: false });
    await expect(controller.verify('x'.repeat(8193))).resolves.toEqual({ confirmed: false });
    await expect(controller.verify('unconfirmed-token')).resolves.toEqual({ confirmed: false });
    expect(getUser).toHaveBeenCalledTimes(1);
  });

  it('rejects a Supabase token validation error', async () => {
    const getUser = jest.fn().mockResolvedValue({
      data: { user: null },
      error: { message: 'Invalid token' },
    });
    const controller = new EmailConfirmationPageController({
      getClient: () => ({ auth: { getUser } }),
    } as never);

    await expect(controller.verify('invalid-token')).resolves.toEqual({ confirmed: false });
  });
});
