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
    const client = this.supabase.getClient();

    const result = await client
      .from('auth_refresh_tokens')
      .select('id, usuario_id, expires_at, revoked_at')
      .eq('token_hash', tokenHash)
      .maybeSingle();

    if (result.error || !result.data) {
      throw new UnauthorizedException('Refresh token inválido.');
    }

    const token = result.data as RefreshTokenRecord;
    if (token.revoked_at || new Date(token.expires_at).getTime() <= Date.now()) {
      throw new UnauthorizedException('Refresh token expirado ou revogado.');
    }

    const newToken = randomBytes(48).toString('base64url');
    const newHash = this.hash(newToken);
    const newExpiresAt = new Date(Date.now() + this.ttlMs).toISOString();

    const inserted = await client
      .from('auth_refresh_tokens')
      .insert({
        usuario_id: token.usuario_id,
        token_hash: newHash,
        expires_at: newExpiresAt,
      })
      .select('id')
      .single();

    if (inserted.error || !inserted.data) {
      throw new UnauthorizedException('Não foi possível renovar a sessão.');
    }

    const revoked = await client
      .from('auth_refresh_tokens')
      .update({
        revoked_at: new Date().toISOString(),
        replaced_by: inserted.data.id,
      })
      .eq('id', token.id)
      .is('revoked_at', null);

    if (revoked.error) {
      await client.from('auth_refresh_tokens').delete().eq('id', inserted.data.id);
      throw new UnauthorizedException('Não foi possível renovar a sessão.');
    }

    return { userId: token.usuario_id, refreshToken: newToken };
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
