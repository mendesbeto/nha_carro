-- Cash commission is recorded as a driver debt; it is not deducted from the
-- driver's wallet at ride completion. Electronic settlement remains atomic and
-- idempotent. Apply only through the normal migration process.

create schema if not exists private;

alter type public.tipo_transacao_enum add value if not exists 'PAGAMENTO_VIAGEM';
alter type public.tipo_transacao_enum add value if not exists 'CREDITO_MOTORISTA';

-- The ledger stores signed entries: debits are negative, credits are positive.
alter table public.transacoes_carteira
  drop constraint if exists transacoes_carteira_valor_check;
alter table public.transacoes_carteira
  drop constraint if exists transacoes_carteira_valor_nonzero_check;
alter table public.transacoes_carteira
  add constraint transacoes_carteira_valor_nonzero_check check (valor <> 0);

create unique index if not exists transacoes_carteira_tipo_referencia_uidx
  on public.transacoes_carteira (tipo, referencia_provedor)
  where referencia_provedor is not null;

create table if not exists public.dividas_comissao_motorista (
  id uuid primary key default uuid_generate_v4(),
  motorista_id uuid not null references public.usuarios(id),
  corrida_id uuid not null unique references public.corridas(id),
  valor numeric(10,2) not null check (valor > 0),
  status text not null default 'PENDENTE'
    check (status in ('PENDENTE', 'PAGA', 'CANCELADA')),
  referencia varchar(120) not null unique,
  criado_em timestamptz not null default current_timestamp,
  paga_em timestamptz,
  constraint dividas_comissao_motorista_paid_at_check
    check ((status = 'PAGA' and paga_em is not null) or status <> 'PAGA')
);

create index if not exists idx_dividas_comissao_motorista_pendentes
  on public.dividas_comissao_motorista (motorista_id, status, criado_em desc);

alter table public.dividas_comissao_motorista enable row level security;
revoke all on public.dividas_comissao_motorista from public, anon, authenticated;
grant select, insert, update on public.dividas_comissao_motorista to service_role;

drop function if exists public.complete_ride_and_settle_wallet(uuid, uuid);
drop function if exists private.complete_ride_and_settle_wallet(uuid, uuid);

create function private.complete_ride_and_settle_wallet(
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
  driver_transaction_id uuid,
  commission_debt_id uuid,
  commission_debt_status text
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
  v_debt_id uuid;
  v_debt_status text;
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
  v_commission := round(greatest(coalesce(v_ride.valor_comissao, 0), 0), 2);

  if v_ride.forma_pagamento = 'DINHEIRO' then
    select u.saldo_carteira
      into v_driver_balance
    from public.usuarios u
    where u.id = p_actor_id
    for update;

    if v_driver_balance is null then
      raise exception 'Carteira do motorista não encontrada.';
    end if;

    if v_commission > 0 then
      insert into public.dividas_comissao_motorista (
        motorista_id, corrida_id, valor, referencia
      )
      values (
        p_actor_id, p_ride_id, v_commission, v_reference || ':COMISSAO'
      )
      on conflict (corrida_id) do nothing;

      select d.id, d.status
        into v_debt_id, v_debt_status
      from public.dividas_comissao_motorista d
      where d.corrida_id = p_ride_id
      for update;

      if v_debt_id is null then
        raise exception 'Não foi possível registar a dívida da comissão.';
      end if;
    end if;

    return query
      select v_ride.id, v_ride.status::text, true, v_ride.valor_total,
             v_driver_balance, null::uuid,
             case when v_debt_id is null
               then 'PAGAMENTO_EM_DINHEIRO_SEM_COMISSAO'
               when v_debt_status = 'PENDENTE'
                 then 'PAGAMENTO_EM_DINHEIRO_DIVIDA_COMISSAO_PENDENTE'
               else 'PAGAMENTO_EM_DINHEIRO_DIVIDA_COMISSAO_JA_REGISTADA'
             end::text,
             v_commission, 0::numeric, v_driver_balance, null::uuid,
             v_debt_id, v_debt_status;
    return;
  end if;

  v_driver_reference := v_reference || ':MOTORISTA';
  v_driver_credit := round(greatest(v_ride.valor_total - v_commission, 0), 2);

  -- Lock wallet rows in a deterministic order to reduce deadlock risk.
  if p_actor_id::text < v_ride.passageiro_id::text then
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

  select t.id into v_transaction_id
  from public.transacoes_carteira t
  where t.tipo = 'PAGAMENTO_VIAGEM'
    and t.referencia_provedor = v_reference
  for update;

  select t.id into v_driver_transaction_id
  from public.transacoes_carteira t
  where t.tipo = 'CREDITO_MOTORISTA'
    and t.referencia_provedor = v_driver_reference
  for update;

  if v_transaction_id is null then
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
      v_ride.passageiro_id, -v_ride.valor_total,
      'PAGAMENTO_VIAGEM', v_reference
    )
    returning id into v_transaction_id;
  end if;

  if v_driver_transaction_id is null and v_driver_credit > 0 then
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
           v_balance, v_transaction_id,
           case when v_driver_transaction_id is not null
                  or v_driver_credit = 0
             then 'LIQUIDADA'
             else 'PAGAMENTO_REGISTADO_CREDITO_PENDENTE'
           end::text,
           v_commission, v_driver_credit, v_driver_balance,
           v_driver_transaction_id, null::uuid, null::text;
end;
$function$;

revoke execute on function private.complete_ride_and_settle_wallet(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.complete_ride_and_settle_wallet(uuid, uuid)
  to service_role;

create function public.complete_ride_and_settle_wallet(
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
  driver_transaction_id uuid,
  commission_debt_id uuid,
  commission_debt_status text
)
language sql
security definer
set search_path = ''
as $$
  select *
  from private.complete_ride_and_settle_wallet($1, $2);
$$;

revoke execute on function public.complete_ride_and_settle_wallet(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.complete_ride_and_settle_wallet(uuid, uuid)
  to service_role;
