-- Allow a narrowly scoped, trusted backend correction from an electronic method
-- to cash for an in-progress ride. All other protected fields remain immutable.
create or replace function private.protect_corrida_changes()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  role_name text := private.my_role();
begin
  if (select auth.role()) = 'service_role'
     and old.status = 'EM_ANDAMENTO'
     and new.status = old.status
     and old.forma_pagamento is distinct from 'DINHEIRO'::public.forma_pagamento_enum
     and new.forma_pagamento = 'DINHEIRO'::public.forma_pagamento_enum
     and new.passageiro_id is not distinct from old.passageiro_id
     and new.motorista_id is not distinct from old.motorista_id
     and new.valor_total is not distinct from old.valor_total
     and new.valor_comissao is not distinct from old.valor_comissao
     and public.st_asewkb(new.origem_coords) is not distinct from public.st_asewkb(old.origem_coords)
     and public.st_asewkb(new.destino_coords) is not distinct from public.st_asewkb(old.destino_coords)
     and new.criado_em is not distinct from old.criado_em then
    return new;
  end if;

  if role_name = 'ADMIN' then return new; end if;

  if new.passageiro_id is distinct from old.passageiro_id
     or new.valor_total is distinct from old.valor_total
     or new.valor_comissao is distinct from old.valor_comissao
     or new.forma_pagamento is distinct from old.forma_pagamento
     or public.st_asewkb(new.origem_coords) is distinct from public.st_asewkb(old.origem_coords)
     or public.st_asewkb(new.destino_coords) is distinct from public.st_asewkb(old.destino_coords)
     or new.criado_em is distinct from old.criado_em then
    raise exception 'Campos financeiros e de origem/destino não podem ser alterados após a criação da corrida';
  end if;

  if role_name = 'PASSAGEIRO' then
    if new.motorista_id is distinct from old.motorista_id then
      raise exception 'O passageiro não pode alterar o motorista da corrida';
    end if;
    if new.status not in ('SOLICITADA','CANCELADA') then
      raise exception 'O passageiro só pode cancelar uma corrida';
    end if;
    if old.status not in ('SOLICITADA','ACEITA') or new.status <> 'CANCELADA' then
      if new.status is distinct from old.status then
        raise exception 'Transição de estado inválida para passageiro';
      end if;
    end if;
    return new;
  end if;

  if role_name = 'MOTORISTA' then
    if new.passageiro_id is distinct from old.passageiro_id
       or new.valor_total is distinct from old.valor_total
       or new.valor_comissao is distinct from old.valor_comissao
       or new.forma_pagamento is distinct from old.forma_pagamento
       or public.st_asewkb(new.origem_coords) is distinct from public.st_asewkb(old.origem_coords)
       or public.st_asewkb(new.destino_coords) is distinct from public.st_asewkb(old.destino_coords) then
      raise exception 'Motorista não pode alterar dados da corrida';
    end if;
    if old.status = 'SOLICITADA' then
      if new.motorista_id is not distinct from old.motorista_id
         or new.motorista_id is distinct from auth.uid()
         or new.status <> 'ACEITA' then
        raise exception 'A aceitação deve atribuir a corrida ao motorista autenticado';
      end if;
    elsif old.status = 'ACEITA' then
      if new.motorista_id <> auth.uid() or new.status <> 'EM_ANDAMENTO' then
        raise exception 'Após aceitar, a próxima transição deve ser EM_ANDAMENTO';
      end if;
    elsif old.status = 'EM_ANDAMENTO' then
      if new.motorista_id <> auth.uid() or new.status <> 'CONCLUIDA' then
        raise exception 'Uma corrida em andamento só pode ser concluída pelo motorista atribuído';
      end if;
    else
      raise exception 'A corrida não pode mais ser alterada pelo motorista';
    end if;
    return new;
  end if;

  raise exception 'Perfil sem permissão para alterar corrida';
end;
$function$;
