-- Fix the driver acceptance transition in protect_corrida_changes.
-- The previous condition rejected every acceptance because motorista_id must
-- change from NULL to the authenticated driver during this transition.

CREATE OR REPLACE FUNCTION private.protect_corrida_changes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  role_name text := private.my_role();
begin
  if role_name = 'ADMIN' then
    return new;
  end if;

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
        raise exception 'Transição de status inválida para passageiro';
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
      if new.motorista_id <> auth.uid()
         or new.status <> 'EM_ANDAMENTO' then
        raise exception 'Após aceitar, a próxima transição deve ser EM_ANDAMENTO';
      end if;
    elsif old.status = 'EM_ANDAMENTO' then
      if new.motorista_id <> auth.uid()
         or new.status <> 'CONCLUIDA' then
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
