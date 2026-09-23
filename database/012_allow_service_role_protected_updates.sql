-- Allow trusted service_role database operations to pass protected-field
-- triggers. Normal authenticated users still require an active ADMIN profile.

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    (select auth.role()) = 'service_role'
    or exists(
      select 1
      from public.usuarios u
      where u.id = (select auth.uid())
        and u.tipo_perfil = 'ADMIN'
        and u.status_conta = 'ATIVO'
    )
$function$;
