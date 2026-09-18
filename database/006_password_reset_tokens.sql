CREATE TABLE IF NOT EXISTS public.auth_password_reset_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id UUID NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  token_hash CHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_auth_password_reset_tokens_usuario
  ON public.auth_password_reset_tokens (usuario_id);

CREATE INDEX IF NOT EXISTS idx_auth_password_reset_tokens_active
  ON public.auth_password_reset_tokens (token_hash, expires_at)
  WHERE used_at IS NULL;

CREATE OR REPLACE FUNCTION public.consume_password_reset_token(
  p_token_hash CHAR(64)
)
RETURNS TABLE (
  user_id UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
  token_record RECORD;
BEGIN
  SELECT id, usuario_id
  INTO token_record
  FROM public.auth_password_reset_tokens
  WHERE token_hash = p_token_hash
    AND used_at IS NULL
    AND expires_at > CURRENT_TIMESTAMP
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE public.auth_password_reset_tokens
  SET used_at = CURRENT_TIMESTAMP
  WHERE id = token_record.id;

  RETURN QUERY SELECT token_record.usuario_id;
END;
$$;

REVOKE ALL ON FUNCTION public.consume_password_reset_token(CHAR(64)) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.consume_password_reset_token(CHAR(64)) TO service_role;
