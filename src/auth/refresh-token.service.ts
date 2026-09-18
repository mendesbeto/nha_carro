import { Injectable, UnauthorizedException } from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import { SupabaseService } from '../supabase/supabase.service';

type RefreshTokenRecord = {
  id: string;
  usuario_id: string;
  expires_at: string;
  revoked_at: string | null;
};

@Injectable()
export class RefreshTokenService {
  private readonly ttlMs = 30 * 24 * 60 * 60 * 1000;

  constructor(private readonly supabase: SupabaseService) {}

  async issue(userId: string): Promise<string> {
    const rawToken = randomBytes(48).toString('base64url');
    const tokenHash = this.hash(rawToken);
    const expiresAt = new Date(Date.now() + this.ttlMs).toISOString();

    const result = await this.supabase.getClient()
      .from('auth_refresh_tokens')
      .insert({
        usuario_id: userId,
        token_hash: tokenHash,
        expires_at: expiresAt,
      });

    if (result.error) {
      throw new UnauthorizedException('Não foi possível criar a sessão.');
    }

    return rawToken;
  }

  async rotate(rawToken: string): Promise<{ userId: string; refreshToken: string }> {
    const tokenHash = this.hash(rawToken);
    const newToken = randomBytes(48).toString('base64url');
    const newHash = this.hash(newToken);
    const newExpiresAt = new Date(Date.now() + this.ttlMs).toISOString();

    const result = await this.supabase.getClient().rpc('rotate_refresh_token', {
      p_token_hash: tokenHash,
      p_new_token_hash: newHash,
      p_expires_at: newExpiresAt,
    });

    if (result.error || !result.data?.length) {
      throw new UnauthorizedException('Refresh token inválido, expirado ou revogado.');
    }

    const row = result.data[0] as {
      user_id: string | null;
      new_token_id: string | null;
      replay_detected: boolean;
    };

    if (row.replay_detected || !row.user_id || !row.new_token_id) {
      throw new UnauthorizedException(
        'Sessão invalidada por reutilização de refresh token.',
      );
    }

    return {
      userId: row.user_id,
      refreshToken: newToken,
    };
  }

  async revokeAll(userId: string): Promise<void> {
    await this.supabase.getClient()
      .from('auth_refresh_tokens')
      .update({ revoked_at: new Date().toISOString() })
      .eq('usuario_id', userId)
      .is('revoked_at', null);
  }

  async revoke(rawToken: string): Promise<void> {
    const tokenHash = this.hash(rawToken);
    await this.supabase.getClient()
      .from('auth_refresh_tokens')
      .update({ revoked_at: new Date().toISOString() })
      .eq('token_hash', tokenHash)
      .is('revoked_at', null);
  }

  private hash(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }
}
