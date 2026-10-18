-- Integration/idempotency test for migration 018.
-- Run ONLY against an isolated disposable database after migrations 001-018.
-- This entire script rolls back; it must never be pointed at production.
begin;

do $test$
declare
  v_passenger uuid := 'a0000000-0000-4000-8000-000000000001';
  v_driver uuid := 'a0000000-0000-4000-8000-000000000002';
  v_cash_ride uuid := 'a0000000-0000-4000-8000-000000000011';
  v_digital_ride uuid := 'a0000000-0000-4000-8000-000000000012';
  v_first record;
  v_second record;
  v_count integer;
  v_passenger_balance numeric;
  v_driver_balance numeric;
begin
  insert into public.usuarios
    (id, nome, telefone, tipo_perfil, saldo_carteira, status_conta)
  values
    (v_passenger, 'TESTE isolado passageiro', '+245900000001', 'PASSAGEIRO', 10000, 'ATIVO'),
    (v_driver, 'TESTE isolado motorista', '+245900000002', 'MOTORISTA', 1000, 'ATIVO');

  insert into public.corridas
    (id, passageiro_id, motorista_id, origem_coords, destino_coords,
     valor_total, valor_comissao, forma_pagamento, status)
  values
    (v_cash_ride, v_passenger, v_driver,
     public.st_setsrid(public.st_makepoint(-15.58, 11.86), 4326),
     public.st_setsrid(public.st_makepoint(-15.57, 11.87), 4326),
     2500, 500, 'DINHEIRO', 'EM_ANDAMENTO'),
    (v_digital_ride, v_passenger, v_driver,
     public.st_setsrid(public.st_makepoint(-15.58, 11.86), 4326),
     public.st_setsrid(public.st_makepoint(-15.57, 11.87), 4326),
     2500, 500, 'ORANGE_MONEY', 'EM_ANDAMENTO');

  select * into v_first
  from public.complete_ride_and_settle_wallet(v_cash_ride, v_driver);
  select * into v_second
  from public.complete_ride_and_settle_wallet(v_cash_ride, v_driver);

  if v_first.settled is distinct from false
     or v_second.settled is distinct from false then
    raise exception 'Corrida em dinheiro não deve ser marcada como liquidação de carteira.';
  end if;

  if v_first.commission_debt_id is null
     or v_first.commission_debt_status <> 'PENDENTE'
     or v_second.commission_debt_id <> v_first.commission_debt_id then
    raise exception 'Falha na idempotência da dívida de comissão em dinheiro.';
  end if;

  select count(*) into v_count
  from public.dividas_comissao_motorista
  where corrida_id = v_cash_ride and motorista_id = v_driver;
  if v_count <> 1 then
    raise exception 'Esperava exatamente uma dívida para a corrida em dinheiro; encontrei %.', v_count;
  end if;

  select saldo_carteira into v_driver_balance
  from public.usuarios where id = v_driver;
  if v_driver_balance <> 1000 then
    raise exception 'A conclusão em dinheiro alterou indevidamente a carteira do motorista: %.', v_driver_balance;
  end if;

  select * into v_first
  from public.complete_ride_and_settle_wallet(v_digital_ride, v_driver);
  select * into v_second
  from public.complete_ride_and_settle_wallet(v_digital_ride, v_driver);

  if v_first.transaction_id is null
     or v_first.driver_transaction_id is null
     or v_second.transaction_id <> v_first.transaction_id
     or v_second.driver_transaction_id <> v_first.driver_transaction_id then
    raise exception 'Falha na idempotência da liquidação eletrónica.';
  end if;

  select saldo_carteira into v_passenger_balance
  from public.usuarios where id = v_passenger;
  select saldo_carteira into v_driver_balance
  from public.usuarios where id = v_driver;

  if v_passenger_balance <> 7500 then
    raise exception 'Saldo do passageiro deveria ser 7500 após um único débito; encontrado %.', v_passenger_balance;
  end if;
  if v_driver_balance <> 3000 then
    raise exception 'Saldo do motorista deveria ser 3000 após um único crédito líquido; encontrado %.', v_driver_balance;
  end if;

  select count(*) into v_count
  from public.transacoes_carteira
  where referencia_provedor in (
    'RIDE:' || v_digital_ride::text,
    'RIDE:' || v_digital_ride::text || ':MOTORISTA'
  );
  if v_count <> 2 then
    raise exception 'Esperava duas transações eletrónicas idempotentes; encontrei %.', v_count;
  end if;
end
$test$;

rollback;
