ALTER TABLE public.usuarios
  ADD COLUMN IF NOT EXISTS session_version INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_usuarios_session_version
  ON public.usuarios (id, session_version);
