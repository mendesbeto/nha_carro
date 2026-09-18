CREATE OR REPLACE FUNCTION public.complete_password_reset(
  p_token_hash CHAR(64),
  p_password_hash TEXT
)
RETURNS TABLE (user_id UUID)
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

  UPDATE public.auth_credentials
  SET password_hash = p_password_hash
  WHERE usuario_id = token_record.usuario_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE public.auth_password_reset_tokens
  SET used_at = CURRENT_TIMESTAMP
  WHERE id = token_record.id;

  RETURN QUERY SELECT token_record.usuario_id;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_password_reset(CHAR(64), TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.complete_password_reset(CHAR(64), TEXT) TO service_role;
