-- Authoritative wallet settlement.
-- Run after the initial schema and Supabase Auth/RLS hardening.

alter type public.tipo_transacao_enum
  add value if not exists 'PAGAMENTO_VIAGEM';

create unique index if not exists transacoes_carteira_tipo_referencia_uidx
on public.transacoes_carteira (tipo, referencia_provedor)
where referencia_provedor is not null;

create or replace function public.complete_ride_and_settle_wallet(
  p_ride_id uuid,
  p_actor_id uuid
)
returns table (
  ride_id uuid,
  status text,
  settled boolean,
  amount numeric,
  balance numeric,
  transaction_id uuid,
  reason text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ride public.corridas%rowtype;
  v_balance numeric;
  v_transaction_id uuid;
  v_reference text;
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);

  select *
    into v_ride
  from public.corridas
  where id = p_ride_id
  for update;

  if not found then
    raise exception 'Corrida não encontrada.';
  end if;

  if v_ride.motorista_id is distinct from p_actor_id then
    raise exception 'Motorista não autorizado para esta corrida.';
  end if;

  if v_ride.status not in ('EM_ANDAMENTO', 'CONCLUIDA') then
    raise exception 'A corrida precisa estar em andamento para ser concluída.';
  end if;

  if v_ride.status = 'EM_ANDAMENTO' then
    update public.corridas
    set status = 'CONCLUIDA'
    where id = p_ride_id
    returning * into v_ride;
  end if;

  if v_ride.forma_pagamento = 'DINHEIRO' then
    select u.saldo_carteira
      into v_balance
    from public.usuarios u
    where u.id = v_ride.passageiro_id
    for update;

    return query
      select v_ride.id, v_ride.status::text, false, 0::numeric,
             coalesce(v_balance, 0), null::uuid, 'PAGAMENTO_EM_DINHEIRO'::text;
    return;
  end if;

  v_reference := 'RIDE:' || p_ride_id::text;

  select t.id
    into v_transaction_id
  from public.transacoes_carteira t
  where t.tipo = 'PAGAMENTO_VIAGEM'
    and t.referencia_provedor = v_reference
  for update;

  select u.saldo_carteira
    into v_balance
  from public.usuarios u
  where u.id = v_ride.passageiro_id
  for update;

  if v_balance is null then
    raise exception 'Carteira do passageiro não encontrada.';
  end if;

  if v_transaction_id is not null then
    return query
      select v_ride.id, v_ride.status::text, true, v_ride.valor_total,
             v_balance, v_transaction_id, 'JA_LIQUIDADA'::text;
    return;
  end if;

  if v_balance < v_ride.valor_total then
    raise exception 'Saldo insuficiente para concluir o pagamento da viagem.';
  end if;

  update public.usuarios
  set saldo_carteira = saldo_carteira - v_ride.valor_total
  where id = v_ride.passageiro_id
  returning saldo_carteira into v_balance;

  insert into public.transacoes_carteira (
    usuario_id, valor, tipo, referencia_provedor
  )
  values (
    v_ride.passageiro_id,
    -v_ride.valor_total,
    'PAGAMENTO_VIAGEM',
    v_reference
  )
  returning id into v_transaction_id;

  return query
    select v_ride.id, v_ride.status::text, true, v_ride.valor_total,
           v_balance, v_transaction_id, 'LIQUIDADA'::text;
end;
$$;

revoke execute on function public.complete_ride_and_settle_wallet(uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.complete_ride_and_settle_wallet(uuid, uuid)
  to service_role;
