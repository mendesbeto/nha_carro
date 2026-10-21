-- Auditable, idempotent administrative settlement of driver commission debts.
-- This records an externally received payment; it never changes wallet balances.

alter table public.dividas_comissao_motorista
  add column if not exists metodo_pagamento text,
  add column if not exists referencia_pagamento varchar(120),
  add column if not exists paga_por uuid references public.usuarios(id);

alter table public.dividas_comissao_motorista
  drop constraint if exists dividas_comissao_motorista_payment_method_check;
alter table public.dividas_comissao_motorista
  add constraint dividas_comissao_motorista_payment_method_check
  check (metodo_pagamento is null or metodo_pagamento in ('DINHEIRO', 'TRANSFERENCIA', 'OUTRO'));

alter table public.dividas_comissao_motorista
  drop constraint if exists dividas_comissao_motorista_paid_audit_check;
alter table public.dividas_comissao_motorista
  add constraint dividas_comissao_motorista_paid_audit_check
  check (
    (status = 'PAGA' and paga_em is not null and paga_por is not null and metodo_pagamento is not null)
    or status <> 'PAGA'
  );

create or replace function private.settle_driver_commission_debt(
  p_debt_id uuid,
  p_admin_id uuid,
  p_payment_method text,
  p_payment_reference text default null
)
returns table (
  debt_id uuid,
  status text,
  amount numeric,
  paid_at timestamptz,
  payment_method text,
  payment_reference text,
  paid_by uuid,
  already_paid boolean
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_admin_role text;
  v_admin_status text;
  v_debt public.dividas_comissao_motorista%rowtype;
  v_method text := upper(trim(coalesce(p_payment_method, '')));
  v_reference text := nullif(trim(coalesce(p_payment_reference, '')), '');
begin
  select u.tipo_perfil::text, u.status_conta::text
    into v_admin_role, v_admin_status
  from public.usuarios u
  where u.id = p_admin_id;

  if v_admin_role is distinct from 'ADMIN' or v_admin_status is distinct from 'ATIVO' then
    raise exception 'Apenas um administrador ativo pode confirmar o pagamento.';
  end if;

  if v_method not in ('DINHEIRO', 'TRANSFERENCIA', 'OUTRO') then
    raise exception 'Método de pagamento inválido.';
  end if;

  if v_reference is not null and length(v_reference) > 120 then
    raise exception 'A referência do pagamento excede 120 caracteres.';
  end if;

  select d.* into v_debt
  from public.dividas_comissao_motorista d
  where d.id = p_debt_id
  for update;

  if not found then
    raise exception 'Dívida de comissão não encontrada.';
  end if;

  if v_debt.status = 'PAGA' then
    return query select v_debt.id, v_debt.status, v_debt.valor, v_debt.paga_em,
      v_debt.metodo_pagamento, v_debt.referencia_pagamento, v_debt.paga_por, true;
    return;
  end if;

  if v_debt.status <> 'PENDENTE' then
    raise exception 'Só é possível liquidar uma dívida pendente.';
  end if;

  update public.dividas_comissao_motorista d
  set status = 'PAGA',
      paga_em = clock_timestamp(),
      metodo_pagamento = v_method,
      referencia_pagamento = v_reference,
      paga_por = p_admin_id
  where d.id = p_debt_id
  returning d.* into v_debt;

  return query select v_debt.id, v_debt.status, v_debt.valor, v_debt.paga_em,
    v_debt.metodo_pagamento, v_debt.referencia_pagamento, v_debt.paga_por, false;
end;
$function$;

revoke all on function private.settle_driver_commission_debt(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function private.settle_driver_commission_debt(uuid, uuid, text, text)
  to service_role;

create or replace function public.settle_driver_commission_debt(
  p_debt_id uuid,
  p_admin_id uuid,
  p_payment_method text,
  p_payment_reference text default null
)
returns table (
  debt_id uuid,
  status text,
  amount numeric,
  paid_at timestamptz,
  payment_method text,
  payment_reference text,
  paid_by uuid,
  already_paid boolean
)
language sql
security definer
set search_path = ''
as $$
  select * from private.settle_driver_commission_debt($1, $2, $3, $4);
$$;

revoke all on function public.settle_driver_commission_debt(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.settle_driver_commission_debt(uuid, uuid, text, text)
  to service_role;
