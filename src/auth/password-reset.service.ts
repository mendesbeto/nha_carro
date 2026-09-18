import { BadRequestException, Injectable } from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import * as bcrypt from 'bcrypt';
import { SupabaseService } from '../supabase/supabase.service';
import { RefreshTokenService } from './refresh-token.service';
import { EmailService } from './email.service';

@Injectable()
export class PasswordResetService {
  private readonly ttlMs = 30 * 60 * 1000;

  constructor(
    private readonly supabase: SupabaseService,
    private readonly refreshTokenService: RefreshTokenService,
    private readonly emailService: EmailService,
  ) {}

  async request(email: string): Promise<void> {
    const normalizedEmail = email.trim().toLowerCase();
    const client = this.supabase.getClient();

    const credentials = await client
      .from('auth_credentials')
      .select('usuario_id')
      .eq('email', normalizedEmail)
      .maybeSingle();

    if (credentials.error || !credentials.data?.usuario_id) {
      return;
    }

    const rawToken = randomBytes(48).toString('base64url');
    const tokenHash = this.hash(rawToken);
    const expiresAt = new Date(Date.now() + this.ttlMs).toISOString();

    await client
      .from('auth_password_reset_tokens')
      .update({ used_at: new Date().toISOString() })
      .eq('usuario_id', credentials.data.usuario_id)
      .is('used_at', null);

    const inserted = await client
      .from('auth_password_reset_tokens')
      .insert({
        usuario_id: credentials.data.usuario_id,
        token_hash: tokenHash,
        expires_at: expiresAt,
      });

    if (inserted.error) {
      return;
    }

    await this.emailService.sendPasswordResetEmail(normalizedEmail, rawToken);
  }

  async reset(
    rawToken: string,
    password: string,
    passwordConfirmation: string,
  ): Promise<void> {
    if (password !== passwordConfirmation) {
      throw new BadRequestException('As senhas não coincidem.');
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const result = await this.supabase.getClient().rpc(
      'complete_password_reset',
      {
        p_token_hash: this.hash(rawToken),
        p_password_hash: passwordHash,
      },
    );

    if (result.error || !result.data?.length) {
      throw new BadRequestException(
        'Token de recuperação inválido ou expirado.',
      );
    }

    const userId = (result.data[0] as { user_id: string }).user_id;
    await this.refreshTokenService.revokeAll(userId);
  }

  private hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
