#!/usr/bin/env bash
set -euo pipefail

: "${PGHOST:=127.0.0.1}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:?PGPASSWORD must be supplied by CI}"
: "${PGDATABASE:=nhacarro_test}"
export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE
PSQL=(psql -X -v ON_ERROR_STOP=1 -q)

"${PSQL[@]}" -f tests/postgres/ride-settlement-fixture.sql

# Stable synthetic IDs only; this database is created by the CI job.
PASSENGER='00000000-0000-4000-8000-000000000001'
DRIVER='00000000-0000-4000-8000-000000000002'
OTHER_DRIVER='00000000-0000-4000-8000-000000000003'
CASH_RIDE='00000000-0000-4000-8000-000000000101'
WALLET_RIDE='00000000-0000-4000-8000-000000000102'
LOW_BALANCE_RIDE='00000000-0000-4000-8000-000000000103'
CANCELLED_RIDE='00000000-0000-4000-8000-000000000104'

"${PSQL[@]}" <<SQL
INSERT INTO public.usuarios(id,nome,telefone,tipo_perfil,status_conta,saldo_carteira) VALUES
('$PASSENGER','CI Passenger','0000000001','PASSAGEIRO','ATIVO',100),
('$DRIVER','CI Driver','0000000002','MOTORISTA','ATIVO',0),
('$OTHER_DRIVER','CI Other Driver','0000000003','MOTORISTA','ATIVO',0);
INSERT INTO public.corridas(id,passageiro_id,motorista_id,valor_total,valor_comissao,forma_pagamento,status) VALUES
('$CASH_RIDE','$PASSENGER','$DRIVER',60,10,'DINHEIRO','EM_ANDAMENTO'),
('$WALLET_RIDE','$PASSENGER','$DRIVER',60,10,'ORANGE_MONEY','EM_ANDAMENTO'),
('$LOW_BALANCE_RIDE','$PASSENGER','$DRIVER',1000,100,'ORANGE_MONEY','EM_ANDAMENTO'),
('$CANCELLED_RIDE','$PASSENGER','$DRIVER',60,10,'ORANGE_MONEY','CANCELADA');
UPDATE public.usuarios SET saldo_carteira=20 WHERE id='$PASSENGER';
SQL

# Cash settlement: two independent PostgreSQL sessions race on the same ride.
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$CASH_RIDE','$DRIVER');" > /tmp/cash-a.out &
p1=$!
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$CASH_RIDE','$DRIVER');" > /tmp/cash-b.out &
p2=$!
wait "$p1"
wait "$p2"

"${PSQL[@]}" <<SQL
DO \$\$
BEGIN
  IF (SELECT status::text FROM public.corridas WHERE id='$CASH_RIDE') <> 'CONCLUIDA' THEN
    RAISE EXCEPTION 'Cash ride was not completed';
  END IF;
  IF (SELECT count(*) FROM public.dividas_comissao_motorista WHERE corrida_id='$CASH_RIDE') <> 1 THEN
    RAISE EXCEPTION 'Concurrent cash completion created duplicate/missing commission debt';
  END IF;
  IF (SELECT valor FROM public.dividas_comissao_motorista WHERE corrida_id='$CASH_RIDE') <> 10 THEN
    RAISE EXCEPTION 'Incorrect cash commission debt amount';
  END IF;
  IF (SELECT count(*) FROM public.transacoes_carteira WHERE referencia_provedor IN ('RIDE:$CASH_RIDE','RIDE:$CASH_RIDE:MOTORISTA')) <> 0 THEN
    RAISE EXCEPTION 'Cash settlement unexpectedly moved wallet funds';
  END IF;
END
\$\$;
SQL
# A sequential retry must not create a second debt.
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$CASH_RIDE','$DRIVER');" >/dev/null
"${PSQL[@]}" -c "DO \$\$ BEGIN IF (SELECT count(*) FROM public.dividas_comissao_motorista WHERE corrida_id='$CASH_RIDE') <> 1 THEN RAISE EXCEPTION 'Cash retry created duplicate debt'; END IF; END \$\$;" 

# Restore sufficient passenger funds, then race wallet settlement.
"${PSQL[@]}" -c "UPDATE public.usuarios SET saldo_carteira=100 WHERE id='$PASSENGER';"
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$WALLET_RIDE','$DRIVER');" > /tmp/wallet-a.out &
p1=$!
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$WALLET_RIDE','$DRIVER');" > /tmp/wallet-b.out &
p2=$!
wait "$p1"
wait "$p2"

"${PSQL[@]}" <<SQL
DO \$\$
BEGIN
  IF (SELECT status::text FROM public.corridas WHERE id='$WALLET_RIDE') <> 'CONCLUIDA' THEN
    RAISE EXCEPTION 'Wallet ride was not completed';
  END IF;
  IF (SELECT saldo_carteira FROM public.usuarios WHERE id='$PASSENGER') <> 40 THEN
    RAISE EXCEPTION 'Passenger wallet was not debited exactly once';
  END IF;
  IF (SELECT saldo_carteira FROM public.usuarios WHERE id='$DRIVER') <> 50 THEN
    RAISE EXCEPTION 'Driver wallet was not credited exactly once';
  END IF;
  IF (SELECT count(*) FROM public.transacoes_carteira WHERE tipo='PAGAMENTO_VIAGEM' AND referencia_provedor='RIDE:$WALLET_RIDE') <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one passenger debit transaction';
  END IF;
  IF (SELECT count(*) FROM public.transacoes_carteira WHERE tipo='CREDITO_MOTORISTA' AND referencia_provedor='RIDE:$WALLET_RIDE:MOTORISTA') <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one driver credit transaction';
  END IF;
END
\$\$;
SQL
# Sequential wallet retry must not change balances or transaction counts.
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$WALLET_RIDE','$DRIVER');" >/dev/null
"${PSQL[@]}" <<SQL
DO \$\$
BEGIN
  IF (SELECT saldo_carteira FROM public.usuarios WHERE id='$PASSENGER') <> 40
     OR (SELECT saldo_carteira FROM public.usuarios WHERE id='$DRIVER') <> 50 THEN
    RAISE EXCEPTION 'Wallet retry changed balances';
  END IF;
  IF (SELECT count(*) FROM public.transacoes_carteira WHERE referencia_provedor IN ('RIDE:$WALLET_RIDE','RIDE:$WALLET_RIDE:MOTORISTA')) <> 2 THEN
    RAISE EXCEPTION 'Wallet retry created duplicate transactions';
  END IF;
END
\$\$;
SQL

# Atomic rollback on insufficient balance.
if "${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$LOW_BALANCE_RIDE','$DRIVER');" >/tmp/low-balance.out 2>&1; then
  echo "Expected insufficient-balance call to fail" >&2
  exit 1
fi
"${PSQL[@]}" <<SQL
DO \$\$
BEGIN
  IF (SELECT status::text FROM public.corridas WHERE id='$LOW_BALANCE_RIDE') <> 'EM_ANDAMENTO' THEN
    RAISE EXCEPTION 'Insufficient-balance failure did not roll back ride status';
  END IF;
  IF EXISTS (SELECT 1 FROM public.transacoes_carteira WHERE referencia_provedor LIKE 'RIDE:$LOW_BALANCE_RIDE%') THEN
    RAISE EXCEPTION 'Insufficient-balance failure left wallet transactions';
  END IF;
END
\$\$;
SQL

# Wrong assigned driver and cancelled ride must fail without financial changes.
if "${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$WALLET_RIDE','$OTHER_DRIVER');" >/tmp/wrong-driver.out 2>&1; then
  echo "Expected wrong-driver call to fail" >&2
  exit 1
fi
if "${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$CANCELLED_RIDE','$DRIVER');" >/tmp/cancelled.out 2>&1; then
  echo "Expected cancelled-ride call to fail" >&2
  exit 1
fi

echo "PASS: PostgreSQL concurrent settlement, retry idempotency, rollback and authorization checks"
