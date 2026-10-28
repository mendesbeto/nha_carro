#!/usr/bin/env bash
set -euo pipefail

# Runs against a disposable PostgreSQL database after the real repository
# migrations 001 and 009-020 have been applied. It deliberately does not
# define/copy the settlement function: the function under test comes from SQL migrations.
: "${PGHOST:=127.0.0.1}"
: "${PGPORT:=5432}"
: "${PGUSER:=postgres}"
: "${PGPASSWORD:?PGPASSWORD must be supplied by CI}"
: "${PGDATABASE:=nhacarro_test}"
export PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE
PSQL=(psql -X -v ON_ERROR_STOP=1 -q)

PASSENGER='b0000000-0000-4000-8000-000000000001'
DRIVER='b0000000-0000-4000-8000-000000000002'
OTHER_DRIVER='b0000000-0000-4000-8000-000000000003'
CASH_RIDE='b0000000-0000-4000-8000-000000000101'
WALLET_RIDE='b0000000-0000-4000-8000-000000000102'
ORANGE_RIDE='b0000000-0000-4000-8000-000000000103'
LOW_BALANCE_RIDE='b0000000-0000-4000-8000-000000000104'
CANCELLED_RIDE='b0000000-0000-4000-8000-000000000105'

"${PSQL[@]}" <<SQL
INSERT INTO public.usuarios(id,nome,telefone,tipo_perfil,status_conta,saldo_carteira) VALUES
('$PASSENGER','Migration CI Passenger','+245910000001','PASSAGEIRO','ATIVO',100),
('$DRIVER','Migration CI Driver','+245910000002','MOTORISTA','ATIVO',0),
('$OTHER_DRIVER','Migration CI Other Driver','+245910000003','MOTORISTA','ATIVO',0);

INSERT INTO public.corridas
(id,passageiro_id,motorista_id,origem_coords,destino_coords,valor_total,valor_comissao,forma_pagamento,status)
VALUES
('$CASH_RIDE','$PASSENGER','$DRIVER',ST_SetSRID(ST_MakePoint(-15.58,11.86),4326),ST_SetSRID(ST_MakePoint(-15.57,11.87),4326),60,10,'DINHEIRO','EM_ANDAMENTO'),
('$WALLET_RIDE','$PASSENGER','$DRIVER',ST_SetSRID(ST_MakePoint(-15.58,11.86),4326),ST_SetSRID(ST_MakePoint(-15.57,11.87),4326),60,10,'CARTEIRA','EM_ANDAMENTO'),
('$LOW_BALANCE_RIDE','$PASSENGER','$DRIVER',ST_SetSRID(ST_MakePoint(-15.58,11.86),4326),ST_SetSRID(ST_MakePoint(-15.57,11.87),4326),1000,100,'CARTEIRA','EM_ANDAMENTO'),
('$CANCELLED_RIDE','$PASSENGER','$DRIVER',ST_SetSRID(ST_MakePoint(-15.58,11.86),4326),ST_SetSRID(ST_MakePoint(-15.57,11.87),4326),60,10,'CARTEIRA','CANCELADA'),
('$ORANGE_RIDE','$PASSENGER','$DRIVER',ST_SetSRID(ST_MakePoint(-15.58,11.86),4326),ST_SetSRID(ST_MakePoint(-15.57,11.87),4326),60,10,'ORANGE_MONEY','EM_ANDAMENTO');
SQL

# Two independent PostgreSQL sessions call the actual migration-created RPC.
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$CASH_RIDE','$DRIVER');" > /tmp/migration-cash-a.out &
p1=$!
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$CASH_RIDE','$DRIVER');" > /tmp/migration-cash-b.out &
p2=$!
wait "$p1"
wait "$p2"

"${PSQL[@]}" <<SQL
DO \$\$
BEGIN
  IF (SELECT status::text FROM public.corridas WHERE id='$CASH_RIDE') <> 'CONCLUIDA' THEN
    RAISE EXCEPTION 'Migration-backed cash ride was not completed';
  END IF;
  IF (SELECT count(*) FROM public.dividas_comissao_motorista WHERE corrida_id='$CASH_RIDE') <> 1 THEN
    RAISE EXCEPTION 'Migration-backed concurrent cash settlement duplicated/missed commission debt';
  END IF;
  IF (SELECT count(*) FROM public.transacoes_carteira WHERE referencia_provedor LIKE 'RIDE:$CASH_RIDE%') <> 0 THEN
    RAISE EXCEPTION 'Cash settlement unexpectedly moved wallet funds';
  END IF;
END
\$\$;
SQL

# Reset passenger balance and race wallet settlement of the migration-created function.
"${PSQL[@]}" -c "UPDATE public.usuarios SET saldo_carteira=100 WHERE id='$PASSENGER';"
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$WALLET_RIDE','$DRIVER');" > /tmp/migration-wallet-a.out &
p1=$!
"${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$WALLET_RIDE','$DRIVER');" > /tmp/migration-wallet-b.out &
p2=$!
wait "$p1"
wait "$p2"

"${PSQL[@]}" <<SQL
DO \$\$
BEGIN
  IF (SELECT status::text FROM public.corridas WHERE id='$WALLET_RIDE') <> 'CONCLUIDA' THEN
    RAISE EXCEPTION 'Migration-backed wallet ride was not completed';
  END IF;
  IF (SELECT saldo_carteira FROM public.usuarios WHERE id='$PASSENGER') <> 40 THEN
    RAISE EXCEPTION 'Passenger wallet was not debited exactly once';
  END IF;
  IF (SELECT saldo_carteira FROM public.usuarios WHERE id='$DRIVER') <> 50 THEN
    RAISE EXCEPTION 'Driver wallet was not credited exactly once';
  END IF;
  IF (SELECT count(*) FROM public.transacoes_carteira WHERE tipo='PAGAMENTO_VIAGEM' AND referencia_provedor='RIDE:$WALLET_RIDE') <> 1 THEN
    RAISE EXCEPTION 'Expected one migration-backed passenger debit';
  END IF;
  IF (SELECT count(*) FROM public.transacoes_carteira WHERE tipo='CREDITO_MOTORISTA' AND referencia_provedor='RIDE:$WALLET_RIDE:MOTORISTA') <> 1 THEN
    RAISE EXCEPTION 'Expected one migration-backed driver credit';
  END IF;
END
\$\$;
SQL

# Failed operations must not mutate status or financial balances.
if "${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$LOW_BALANCE_RIDE','$DRIVER');" >/tmp/migration-low-balance.out 2>&1; then
  echo "Expected migration-backed insufficient-balance call to fail" >&2
  exit 1
fi
if "${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$ORANGE_RIDE','$DRIVER');" >/tmp/migration-orange.out 2>&1; then
  echo "Expected migration-backed unconfirmed Orange Money call to fail" >&2
  exit 1
fi
if "${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$WALLET_RIDE','$OTHER_DRIVER');" >/tmp/migration-wrong-driver.out 2>&1; then
  echo "Expected migration-backed wrong-driver call to fail" >&2
  exit 1
fi
if "${PSQL[@]}" -c "SELECT * FROM public.complete_ride_and_settle_wallet('$CANCELLED_RIDE','$DRIVER');" >/tmp/migration-cancelled.out 2>&1; then
  echo "Expected migration-backed cancelled-ride call to fail" >&2
  exit 1
fi

"${PSQL[@]}" <<SQL
DO \$\$
BEGIN
  IF (SELECT status::text FROM public.corridas WHERE id='$LOW_BALANCE_RIDE') <> 'EM_ANDAMENTO' THEN
    RAISE EXCEPTION 'Insufficient balance changed ride status';
  END IF;
  IF (SELECT status::text FROM public.corridas WHERE id='$ORANGE_RIDE') <> 'EM_ANDAMENTO' THEN
    RAISE EXCEPTION 'Unconfirmed Orange Money changed ride status';
  END IF;
  IF EXISTS (SELECT 1 FROM public.transacoes_carteira WHERE referencia_provedor LIKE 'RIDE:$LOW_BALANCE_RIDE%' OR referencia_provedor LIKE 'RIDE:$ORANGE_RIDE%') THEN
    RAISE EXCEPTION 'Rejected operation left wallet transactions';
  END IF;
  IF (SELECT saldo_carteira FROM public.usuarios WHERE id='$PASSENGER') <> 40
     OR (SELECT saldo_carteira FROM public.usuarios WHERE id='$DRIVER') <> 50 THEN
    RAISE EXCEPTION 'Rejected operation changed wallet balances';
  END IF;
END
\$\$;
SQL

echo "PASS: real migrations 001 and 009-020: concurrent cash/wallet settlement, idempotency, rollback and authorization"
