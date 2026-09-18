-- Refresh tokens rotativos para sessões móveis.
CREATE TABLE IF NOT EXISTS public.auth_refresh_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id UUID NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  replaced_by UUID REFERENCES public.auth_refresh_tokens(id),
  criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_auth_refresh_tokens_usuario
  ON public.auth_refresh_tokens (usuario_id);

CREATE INDEX IF NOT EXISTS idx_auth_refresh_tokens_active
  ON public.auth_refresh_tokens (token_hash, expires_at)
  WHERE revoked_at IS NULL;
