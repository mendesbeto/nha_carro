-- Credenciais da API. A senha nunca é armazenada em texto puro.
-- O Flutter envia o e-mail e, temporariamente, ele ocupa usuarios.telefone.
ALTER TABLE public.usuarios
  ALTER COLUMN telefone TYPE VARCHAR(320);

CREATE TABLE IF NOT EXISTS public.auth_credentials (
  usuario_id UUID PRIMARY KEY REFERENCES public.usuarios(id) ON DELETE CASCADE,
  email VARCHAR(320) NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  criado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_auth_credentials_email
  ON public.auth_credentials (email);
