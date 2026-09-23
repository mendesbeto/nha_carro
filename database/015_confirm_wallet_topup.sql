create schema if not exists private;

create or replace function private.confirm_wallet_top_up(
  p_topup_id uuid,
  p_provider_reference text,
  p_amount numeric,
  p_provider_response jsonb default null
)
returns table (
  topup_id uuid,
  status text,
  balance numeric,
  transaction_id uuid,
  already_confirmed boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_topup public.recargas_carteira%rowtype;
  v_balance numeric;
  v_transaction_id uuid;
  v_reference text;
  v_type public.tipo_transacao_enum;
begin
  if p_provider_reference is null or length(trim(p_provider_reference)) = 0 then
    raise exception 'Referência do provedor obrigatória.';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Valor de confirmação inválido.';
  end if;

  select *
    into v_topup
  from public.recargas_carteira
  where id = p_topup_id
  for update;

  if not found then
    raise exception 'Recarga não encontrada.';
  end if;

  if v_topup.status = 'CONFIRMADA' then
    select u.saldo_carteira
      into v_balance
    from public.usuarios u
    where u.id = v_topup.usuario_id;

    select t.id
      into v_transaction_id
    from public.transacoes_carteira t
    where t.tipo = case
      when v_topup.metodo = 'ORANGE_MONEY' then 'RECARGA_ORANGE'::public.tipo_transacao_enum
      else 'RECARGA_MTN'::public.tipo_transacao_enum
    end
      and t.referencia_provedor = 'TOPUP:' || v_topup.id::text
    limit 1;

    return query
      select v_topup.id, v_topup.status, coalesce(v_balance, 0),
             v_transaction_id, true;
    return;
  end if;

  if round(v_topup.valor, 2) <> round(p_amount, 2) then
    raise exception 'Valor confirmado pelo provedor não corresponde à recarga.';
  end if;

  if v_topup.status not in ('PENDENTE', 'PROCESSANDO') then
    raise exception 'A recarga não está em estado confirmável.';
  end if;

  if v_topup.referencia_provedor is not null
     and v_topup.referencia_provedor <> p_provider_reference then
    raise exception 'Referência do provedor não corresponde à recarga.';
  end if;

  v_reference := 'TOPUP:' || v_topup.id::text;
  v_type := case
    when v_topup.metodo = 'ORANGE_MONEY'
      then 'RECARGA_ORANGE'::public.tipo_transacao_enum
    else 'RECARGA_MTN'::public.tipo_transacao_enum
  end;

  update public.usuarios
  set saldo_carteira = coalesce(saldo_carteira, 0) + round(v_topup.valor, 2)
  where id = v_topup.usuario_id
  returning saldo_carteira into v_balance;

  if v_balance is null then
    raise exception 'Carteira do usuário não encontrada.';
  end if;

  insert into public.transacoes_carteira (
    usuario_id, valor, tipo, referencia_provedor
  )
  values (
    v_topup.usuario_id, round(v_topup.valor, 2), v_type, v_reference
  )
  on conflict do nothing
  returning id into v_transaction_id;

  if v_transaction_id is null then
    select t.id
      into v_transaction_id
    from public.transacoes_carteira t
    where t.tipo = v_type
      and t.referencia_provedor = v_reference
    limit 1;
  end if;

  update public.recargas_carteira
  set status = 'CONFIRMADA',
      referencia_provedor = p_provider_reference,
      resposta_provedor = p_provider_response
  where id = v_topup.id;

  return query
    select v_topup.id, 'CONFIRMADA'::text, v_balance,
           v_transaction_id, false;
end;
$$;

revoke execute on function private.confirm_wallet_top_up(uuid, text, numeric, jsonb)
  from public, anon, authenticated;

grant execute on function private.confirm_wallet_top_up(uuid, text, numeric, jsonb)
  to service_role;
