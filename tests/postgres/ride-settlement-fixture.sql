-- Isolated PostgreSQL fixture for concurrency regression testing.
-- This is a minimal schema, not a replacement for the production Supabase migrations.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TYPE public.status_corrida_enum AS ENUM ('SOLICITADA', 'ACEITA', 'EM_ANDAMENTO', 'CONCLUIDA', 'CANCELADA');
CREATE TYPE public.forma_pagamento_enum AS ENUM ('DINHEIRO', 'ORANGE_MONEY', 'MTN_MONEY');
CREATE TYPE public.tipo_transacao_enum AS ENUM ('PAGAMENTO_VIAGEM', 'CREDITO_MOTORISTA', 'DEDUCAO_COMISSAO');

CREATE TABLE public.usuarios (
  id uuid PRIMARY KEY,
  nome text NOT NULL,
  telefone varchar NOT NULL,
  tipo_perfil text NOT NULL,
  status_conta text DEFAULT 'ATIVO',
  saldo_carteira numeric DEFAULT 0.00
);

CREATE TABLE public.corridas (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  passageiro_id uuid NOT NULL REFERENCES public.usuarios(id),
  motorista_id uuid REFERENCES public.usuarios(id),
  valor_total numeric NOT NULL,
  valor_comissao numeric NOT NULL,
  forma_pagamento public.forma_pagamento_enum NOT NULL,
  status public.status_corrida_enum DEFAULT 'SOLICITADA'
);

CREATE TABLE public.transacoes_carteira (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id uuid NOT NULL REFERENCES public.usuarios(id),
  valor numeric NOT NULL,
  tipo public.tipo_transacao_enum NOT NULL,
  referencia_provedor varchar,
  criado_em timestamptz DEFAULT CURRENT_TIMESTAMP
);
CREATE UNIQUE INDEX transacoes_carteira_tipo_referencia_uq
  ON public.transacoes_carteira(tipo, referencia_provedor)
  WHERE referencia_provedor IS NOT NULL;

CREATE TABLE public.dividas_comissao_motorista (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  motorista_id uuid NOT NULL REFERENCES public.usuarios(id),
  corrida_id uuid NOT NULL UNIQUE REFERENCES public.corridas(id),
  valor numeric NOT NULL,
  status text NOT NULL DEFAULT 'PENDENTE',
  referencia varchar NOT NULL,
  criado_em timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Test-only delay makes the competing session reliably wait on the ride row lock.
CREATE OR REPLACE FUNCTION public.test_pause_on_ride_completion()
RETURNS trigger LANGUAGE plpgsql AS $trigger$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'CONCLUIDA' THEN
    PERFORM pg_sleep(0.8);
  END IF;
  RETURN NEW;
END;
$trigger$;
CREATE TRIGGER test_pause_on_ride_completion
BEFORE UPDATE OF status ON public.corridas
FOR EACH ROW EXECUTE FUNCTION public.test_pause_on_ride_completion();

CREATE SCHEMA IF NOT EXISTS private;

-- Function body copied from the read-only production definition on 2026-10-25.
-- Keep changes to this fixture aligned with production SQL and review diffs carefully.
CREATE OR REPLACE FUNCTION private.complete_ride_and_settle_wallet(p_ride_id uuid, p_actor_id uuid)
RETURNS TABLE(
  ride_id uuid, status text, settled boolean, amount numeric, balance numeric,
  transaction_id uuid, reason text, commission numeric, driver_credit numeric,
  driver_balance numeric, driver_transaction_id uuid, commission_debt_id uuid,
  commission_debt_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
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
  v_existing_commission_transaction_id uuid;
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

    select t.id
      into v_existing_commission_transaction_id
    from public.transacoes_carteira t
    where t.tipo = 'DEDUCAO_COMISSAO'
      and t.referencia_provedor = v_reference || ':COMISSAO'
    for update;

    if v_existing_commission_transaction_id is not null then
      return query
        select v_ride.id, v_ride.status::text, false, v_ride.valor_total,
               v_driver_balance, null::uuid,
               'PAGAMENTO_EM_DINHEIRO_COMISSAO_JA_DEBITADA'::text,
               v_commission, 0::numeric, v_driver_balance, null::uuid,
               null::uuid, null::text;
      return;
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
      select v_ride.id, v_ride.status::text, false, v_ride.valor_total,
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
      p_actor_id, v_driver_credit, 'CREDITO_MOTORISTA', v_driver_reference
    )
    returning id into v_driver_transaction_id;
  end if;

  return query
    select v_ride.id, v_ride.status::text, true, v_ride.valor_total,
           v_balance, v_transaction_id,
           case when v_driver_transaction_id is not null or v_driver_credit = 0
             then 'LIQUIDADA'
             else 'PAGAMENTO_REGISTADO_CREDITO_PENDENTE'
           end::text,
           v_commission, v_driver_credit, v_driver_balance,
           v_driver_transaction_id, null::uuid, null::text;
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_ride_and_settle_wallet(p_ride_id uuid, p_actor_id uuid)
RETURNS TABLE(
  ride_id uuid, status text, settled boolean, amount numeric, balance numeric,
  transaction_id uuid, reason text, commission numeric, driver_credit numeric,
  driver_balance numeric, driver_transaction_id uuid, commission_debt_id uuid,
  commission_debt_status text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path TO ''
AS $function$
  select * from private.complete_ride_and_settle_wallet($1, $2);
$function$;
