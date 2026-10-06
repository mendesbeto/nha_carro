-- Cash ride settlement.
-- Passenger pays the driver in cash. The platform does not debit the
-- passenger wallet; instead, the driver's commission is deducted from
-- the driver's wallet when the driver confirms completion.
--
-- Privileged business logic lives in private; the public wrapper is
-- service-role-only.

create schema if not exists private;

alter type public.tipo_transacao_enum
  add value if not exists 'PAGAMENTO_VIAGEM';

alter type public.tipo_transacao_enum
  add value if not exists 'CREDITO_MOTORISTA';

create unique index if not exists transacoes_carteira_tipo_referencia_uidx
  on public.transacoes_carteira (tipo, referencia_provedor)
  where referencia_provedor is not null;

drop function if exists public.complete_ride_and_settle_wallet(uuid, uuid);
drop function if exists private.complete_ride_and_settle_wallet(uuid, uuid);

create or replace function private.complete_ride_and_settle_wallet(
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
  reason text,
  commission numeric,
  driver_credit numeric,
  driver_balance numeric,
  driver_transaction_id uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_ride public.corridas%rowtype;
  v_balance numeric;
  v_driver_balance numeric;
  v_transaction_id uuid;
  v_driver_transaction_id uuid;
  v_reference text;
  v_driver_reference text;
  v_driver_role text;
  v_driver_status text;
  v_commission numeric;
  v_driver_credit numeric;
begin
  perform set_config('request.jwt.claim.sub', p_actor_id::text, true);

  select u.tipo_perfil::text, u.status_conta::text
    into v_driver_role, v_driver_status
  from public.usuarios u
  where u.id = p_actor_id;

  if v_driver_role is distinct from 'MOTORISTA'
     or v_driver_status is distinct from 'ATIVO' then
    raise exception 'Motorista não autorizado para liquidar esta corrida.';
  end if;

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

  v_reference := 'RIDE:' || p_ride_id::text;

  if v_ride.forma_pagamento = 'DINHEIRO' then
    v_driver_reference := v_reference || ':COMISSAO';
    v_commission := round(greatest(coalesce(v_ride.valor_comissao, 0), 0), 2);

    select u.saldo_carteira
      into v_driver_balance
    from public.usuarios u
    where u.id = p_actor_id
    for update;

    if v_driver_balance is null then
      raise exception 'Carteira do motorista não encontrada.';
    end if;

    select t.id
      into v_driver_transaction_id
    from public.transacoes_carteira t
    where t.tipo = 'DEDUCAO_COMISSAO'
      and t.referencia_provedor = v_driver_reference
    for update;

    if v_driver_transaction_id is not null then
      return query
        select v_ride.id, v_ride.status::text, true, v_ride.valor_total,
               v_driver_balance, v_driver_transaction_id,
               'PAGAMENTO_EM_DINHEIRO_JA_CONFIRMADO'::text,
               v_commission, 0::numeric, v_driver_balance,
               v_driver_transaction_id;
      return;
    end if;

    if v_driver_balance < v_commission then
      raise exception 'Saldo insuficiente para pagar a comissão da viagem.';
    end if;

    if v_commission > 0 then
      update public.usuarios
      set saldo_carteira = saldo_carteira - v_commission
      where id = p_actor_id
      returning saldo_carteira into v_driver_balance;

      insert into public.transacoes_carteira (
        usuario_id, valor, tipo, referencia_provedor
      )
      values (
        p_actor_id, -v_commission,
        'DEDUCAO_COMISSAO', v_driver_reference
      )
      returning id into v_driver_transaction_id;
    end if;

    return query
      select v_ride.id, v_ride.status::text, true, v_ride.valor_total,
             v_driver_balance, v_driver_transaction_id,
             'PAGAMENTO_EM_DINHEIRO_CONFIRMADO'::text,
             v_commission, 0::numeric, v_driver_balance,
             v_driver_transaction_id;
    return;
  end if;

  v_driver_reference := v_reference || ':MOTORISTA';
  v_commission := round(greatest(coalesce(v_ride.valor_comissao, 0), 0), 2);
  v_driver_credit := round(greatest(v_ride.valor_total - v_commission, 0), 2);

  if p_actor_id < v_ride.passageiro_id then
    select u.saldo_carteira into v_driver_balance
    from public.usuarios u where u.id = p_actor_id for update;
    select u.saldo_carteira into v_balance
    from public.usuarios u where u.id = v_ride.passageiro_id for update;
  else
    select u.saldo_carteira into v_balance
    from public.usuarios u where u.id = v_ride.passageiro_id for update;
    select u.saldo_carteira into v_driver_balance
    from public.usuarios u where u.id = p_actor_id for update;
  end if;

  if v_balance is null then
    raise exception 'Carteira do passageiro não encontrada.';
  end if;

  if v_driver_balance is null then
    raise exception 'Carteira do motorista não encontrada.';
  end if;

  select t.id
    into v_transaction_id
  from public.transacoes_carteira t
  where t.tipo = 'PAGAMENTO_VIAGEM'
    and t.referencia_provedor = v_reference
  for update;

  select t.id
    into v_driver_transaction_id
  from public.transacoes_carteira t
  where t.tipo = 'CREDITO_MOTORISTA'
    and t.referencia_provedor = v_driver_reference
  for update;

  if v_transaction_id is not null
     and v_driver_transaction_id is not null then
    return query
      select v_ride.id, v_ride.status::text, true, v_ride.valor_total,
             v_balance, v_transaction_id, 'JA_LIQUIDADA'::text,
             v_commission, v_driver_credit, v_driver_balance,
             v_driver_transaction_id;
    return;
  end if;

  if v_balance < v_ride.valor_total then
    raise exception 'Saldo insuficiente para concluir o pagamento da viagem.';
  end if;

  if v_transaction_id is null then
    update public.usuarios
    set saldo_carteira = saldo_carteira - v_ride.valor_total
    where id = v_ride.passageiro_id
    returning saldo_carteira into v_balance;

    insert into public.transacoes_carteira (
      usuario_id, valor, tipo, referencia_provedor
    )
    values (
      v_ride.passageiro_id, -v_ride.valor_total,
      'PAGAMENTO_VIAGEM', v_reference
    )
    returning id into v_transaction_id;
  end if;

  if v_driver_transaction_id is null then
    update public.usuarios
    set saldo_carteira = saldo_carteira + v_driver_credit
    where id = p_actor_id
    returning saldo_carteira into v_driver_balance;

    insert into public.transacoes_carteira (
      usuario_id, valor, tipo, referencia_provedor
    )
    values (
      p_actor_id, v_driver_credit,
      'CREDITO_MOTORISTA', v_driver_reference
    )
    returning id into v_driver_transaction_id;
  end if;

  return query
    select v_ride.id, v_ride.status::text, true, v_ride.valor_total,
           v_balance, v_transaction_id, 'LIQUIDADA'::text,
           v_commission, v_driver_credit, v_driver_balance,
           v_driver_transaction_id;
end;
$function$;

revoke execute
  on function private.complete_ride_and_settle_wallet(uuid, uuid)
  from public, anon, authenticated;

grant execute
  on function private.complete_ride_and_settle_wallet(uuid, uuid)
  to service_role;

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
  reason text,
  commission numeric,
  driver_credit numeric,
  driver_balance numeric,
  driver_transaction_id uuid
)
language sql
set search_path = public, private
as $$
  select *
  from private.complete_ride_and_settle_wallet($1, $2);
$$;

revoke execute
  on function public.complete_ride_and_settle_wallet(uuid, uuid)
  from public, anon, authenticated;

grant execute
  on function public.complete_ride_and_settle_wallet(uuid, uuid)
  to service_role;
