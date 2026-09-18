CREATE OR REPLACE FUNCTION public.rotate_refresh_token(
  p_token_hash CHAR(64),
  p_new_token_hash CHAR(64),
  p_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
  user_id UUID,
  new_token_id UUID,
  replay_detected BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
  current_token RECORD;
  created_token_id UUID;
BEGIN
  SELECT id, usuario_id, revoked_at, expires_at
  INTO current_token
  FROM public.auth_refresh_tokens
  WHERE token_hash = p_token_hash
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT NULL::UUID, NULL::UUID, FALSE;
    RETURN;
  END IF;

  IF current_token.revoked_at IS NOT NULL THEN
    UPDATE public.auth_refresh_tokens
    SET revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP)
    WHERE usuario_id = current_token.usuario_id
      AND revoked_at IS NULL;

    RETURN QUERY SELECT current_token.usuario_id, NULL::UUID, TRUE;
    RETURN;
  END IF;

  IF current_token.expires_at <= CURRENT_TIMESTAMP THEN
    UPDATE public.auth_refresh_tokens
    SET revoked_at = CURRENT_TIMESTAMP
    WHERE id = current_token.id
      AND revoked_at IS NULL;

    RETURN QUERY SELECT NULL::UUID, NULL::UUID, FALSE;
    RETURN;
  END IF;

  INSERT INTO public.auth_refresh_tokens (
    usuario_id,
    token_hash,
    expires_at
  )
  VALUES (
    current_token.usuario_id,
    p_new_token_hash,
    p_expires_at
  )
  RETURNING id INTO created_token_id;

  UPDATE public.auth_refresh_tokens
  SET revoked_at = CURRENT_TIMESTAMP,
      replaced_by = created_token_id
  WHERE id = current_token.id;

  RETURN QUERY
  SELECT current_token.usuario_id, created_token_id, FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.rotate_refresh_token(CHAR(64), CHAR(64), TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rotate_refresh_token(CHAR(64), CHAR(64), TIMESTAMPTZ) TO service_role;
