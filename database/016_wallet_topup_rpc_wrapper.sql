create or replace function public.confirm_wallet_top_up(
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
language sql
set search_path = public, private
as $$
  select *
  from private.confirm_wallet_top_up(
    p_topup_id,
    p_provider_reference,
    p_amount,
    p_provider_response
  );
$$;

-- The backend reaches this wrapper with the Supabase service_role key.
-- Never expose the wallet-confirmation RPC to client roles.
revoke execute on function public.confirm_wallet_top_up(uuid, text, numeric, jsonb)
  from public, anon, authenticated;

grant execute on function public.confirm_wallet_top_up(uuid, text, numeric, jsonb)
  to service_role;
