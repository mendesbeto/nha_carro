import {
  BadRequestException,
  Injectable,
} from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import * as bcrypt from 'bcrypt';
import { SupabaseService } from '../supabase/supabase.service';
import { RefreshTokenService } from './refresh-token.service';

@Injectable()
export class PasswordResetService {
  private readonly ttlMs = 30 * 60 * 1000;

  constructor(
    private readonly supabase: SupabaseService,
    private readonly refreshTokenService: RefreshTokenService,
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
      throw new BadRequestException('Não foi possível iniciar a recuperação.');
    }

    // The raw token must only be delivered through the configured side-channel.
    // It is intentionally never returned or logged by the API.
  }

  async reset(
    rawToken: string,
    password: string,
    passwordConfirmation: string,
  ): Promise<void> {
    if (password !== passwordConfirmation) {
      throw new BadRequestException('As senhas não coincidem.');
    }

    const tokenHash = this.hash(rawToken);
    const result = await this.supabase.getClient().rpc(
      'consume_password_reset_token',
      { p_token_hash: tokenHash },
    );

    if (result.error || !result.data?.length) {
      throw new BadRequestException('Token de recuperação inválido ou expirado.');
    }

    const userId = (result.data[0] as { user_id: string }).user_id;
    const passwordHash = await bcrypt.hash(password, 12);

    const updated = await this.supabase
      .getClient()
      .from('auth_credentials')
      .update({ password_hash: passwordHash })
      .eq('usuario_id', userId);

    if (updated.error) {
      throw new BadRequestException('Não foi possível atualizar a senha.');
    }

    await this.refreshTokenService.revokeAll(userId);
  }

  private hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
