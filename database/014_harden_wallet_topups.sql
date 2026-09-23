-- Wallet top-up idempotency is scoped to the authenticated user.
alter table public.recargas_carteira
  drop constraint if exists recargas_carteira_chave_idempotencia_key;

create unique index if not exists recargas_carteira_usuario_idempotency_idx
  on public.recargas_carteira(usuario_id, chave_idempotencia);

-- Clients may read their own top-up status, but must not create or mutate
-- payment records directly. The backend owns the payment lifecycle.
revoke insert, update, delete on public.recargas_carteira from authenticated;
grant select on public.recargas_carteira to authenticated;
