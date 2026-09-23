-- Controlled wallet top-up for end-to-end sandbox testing only.
-- Execution is restricted to service_role; the API enables the endpoint only
-- when WALLET_TEST_MODE=true.

create or replace function public.test_top_up_wallet(
  p_user_id uuid,
  p_amount numeric,
  p_type text
)
returns table (
  balance numeric,
  amount numeric,
  type text,
  transaction_id uuid,
  reference text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_balance numeric;
  v_transaction_id uuid;
  v_reference text;
begin
  if p_amount <= 0 or p_amount > 10000 then
    raise exception 'Valor de recarga de teste inválido.';
  end if;

  if p_type not in ('RECARGA_ORANGE', 'RECARGA_MTN') then
    raise exception 'Tipo de recarga inválido.';
  end if;

  v_reference := 'TEST-TOPUP:' || gen_random_uuid()::text;

  update public.usuarios
  set saldo_carteira = coalesce(saldo_carteira, 0) + round(p_amount, 2)
  where id = p_user_id
  returning saldo_carteira into v_balance;

  if v_balance is null then
    raise exception 'Usuário não encontrado.';
  end if;

  insert into public.transacoes_carteira (
    usuario_id, valor, tipo, referencia_provedor
  )
  values (
    p_user_id, round(p_amount, 2), p_type::public.tipo_transacao_enum, v_reference
  )
  returning id into v_transaction_id;

  return query
    select v_balance, round(p_amount, 2), p_type, v_transaction_id, v_reference;
end;
$$;

revoke execute on function public.test_top_up_wallet(uuid, numeric, text)
  from public, anon, authenticated;

grant execute on function public.test_top_up_wallet(uuid, numeric, text)
  to service_role;
