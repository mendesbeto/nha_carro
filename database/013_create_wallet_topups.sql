-- Recargas pendentes da carteira para integração Orange Money / MTN MoMo.
-- O saldo da carteira só deve ser creditado após confirmação do provedor.

create table if not exists public.recargas_carteira (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios(id) on delete cascade,
  valor numeric(12,2) not null check (valor > 0 and valor <= 100000),
  metodo text not null check (metodo in ('ORANGE_MONEY','MTN_MONEY')),
  status text not null default 'PENDENTE'
    check (status in ('PENDENTE','PROCESSANDO','CONFIRMADA','FALHOU','EXPIRADA')),
  referencia_provedor text,
  chave_idempotencia text not null unique,
  checkout_url text,
  resposta_provedor jsonb,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);

create unique index if not exists recargas_carteira_provider_ref_idx
  on public.recargas_carteira(referencia_provedor)
  where referencia_provedor is not null;

create index if not exists recargas_carteira_usuario_status_idx
  on public.recargas_carteira(usuario_id, status, criado_em desc);

alter table public.recargas_carteira enable row level security;

drop policy if exists recargas_select_own on public.recargas_carteira;
create policy recargas_select_own
on public.recargas_carteira
for select to authenticated
using (usuario_id = auth.uid());

drop policy if exists recargas_insert_own on public.recargas_carteira;
create policy recargas_insert_own
on public.recargas_carteira
for insert to authenticated
with check (usuario_id = auth.uid());

grant select, insert on public.recargas_carteira to authenticated;
grant select, insert, update, delete on public.recargas_carteira to service_role;

create or replace function public.touch_recargas_carteira()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

drop trigger if exists trg_touch_recargas_carteira on public.recargas_carteira;
create trigger trg_touch_recargas_carteira
before update on public.recargas_carteira
for each row execute function public.touch_recargas_carteira();
