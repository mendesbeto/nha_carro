CREATE OR REPLACE FUNCTION public.rotate_refresh_token(
  p_token_hash CHAR(64),
  p_new_token_hash CHAR(64),
  p_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
  user_id UUID,
  new_token_id UUID
)
LANGUAGE plpgsql
AS $$
DECLARE
  current_token_id UUID;
  current_user_id UUID;
  created_token_id UUID;
BEGIN
  UPDATE public.auth_refresh_tokens
  SET revoked_at = CURRENT_TIMESTAMP
  WHERE token_hash = p_token_hash
    AND revoked_at IS NULL
    AND expires_at > CURRENT_TIMESTAMP
  RETURNING id, usuario_id
  INTO current_token_id, current_user_id;

  IF current_token_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.auth_refresh_tokens (
    usuario_id,
    token_hash,
    expires_at
  )
  VALUES (
    current_user_id,
    p_new_token_hash,
    p_expires_at
  )
  RETURNING id INTO created_token_id;

  UPDATE public.auth_refresh_tokens
  SET replaced_by = created_token_id
  WHERE id = current_token_id;

  RETURN QUERY
  SELECT current_user_id, created_token_id;
END;
$$;

REVOKE ALL ON FUNCTION public.rotate_refresh_token(CHAR(64), CHAR(64), TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rotate_refresh_token(CHAR(64), CHAR(64), TIMESTAMPTZ) TO service_role;
