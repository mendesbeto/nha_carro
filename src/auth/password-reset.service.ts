import { BadRequestException, Injectable } from '@nestjs/common';
import { SupabaseService } from '../supabase/supabase.service';
import { EmailService } from './email.service';

@Injectable()
export class PasswordResetService {
  constructor(
    private readonly supabase: SupabaseService,
    private readonly emailService: EmailService,
  ) {}

  async request(email: string): Promise<void> {
    const normalizedEmail = email.trim().toLowerCase();
    const redirectTo = process.env.PASSWORD_RESET_URL;
    if (!redirectTo) return;

    const result = await this.supabase.getClient().auth.admin.generateLink({
      type: 'recovery',
      email: normalizedEmail,
      options: { redirectTo },
    });

    if (result.error || !result.data?.properties?.action_link) return;
    await this.emailService.sendSupabasePasswordResetEmail(
      normalizedEmail,
      result.data.properties.action_link,
    );
  }

  async reset(rawToken: string, password: string, passwordConfirmation: string): Promise<void> {
    // Legacy endpoint retained temporarily for source compatibility. New recovery links use Supabase Auth access tokens.
    return this.resetWithAccessToken(rawToken, password, passwordConfirmation);
  }

  async resetWithAccessToken(
    accessToken: string,
    password: string,
    passwordConfirmation: string,
  ): Promise<void> {
    if (!accessToken || password.length < 8 || password !== passwordConfirmation) {
      throw new BadRequestException('Dados de recuperação inválidos.');
    }

    const client = this.supabase.getClient();
    const authUser = await client.auth.getUser(accessToken);
    if (authUser.error || !authUser.data.user) {
      throw new BadRequestException('Sessão de recuperação inválida ou expirada.');
    }

    const updated = await client.auth.admin.updateUserById(authUser.data.user.id, {
      password,
    });
    if (updated.error) {
      throw new BadRequestException('Não foi possível alterar a palavra-passe.');
    }

    // Revoke all refresh-token sessions after a password reset.
    await client.auth.admin.signOut(accessToken);
  }
}
