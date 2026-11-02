-- ASOINCO · Reserva web: ahora ASOINCO envía la factura (el socio ya no sube comprobante)
-- y las reservas web YA NO se liberan solas (los operadores deciden).
-- Pegar COMPLETO en Supabase (proyecto ASOINCO) → SQL Editor → Run (una sola vez).

alter table expo_inscripciones add column if not exists factura_enviada_at timestamptz;

-- Se apaga la liberación automática cada hora
do $$
begin
  if exists (select 1 from cron.job where jobname = 'expo-liberar-reservas') then
    perform cron.unschedule('expo-liberar-reservas');
  end if;
end $$;

-- Las reservas web que ya existen quedan sin fecha de vencimiento
update expo_inscripciones set vence_at = null where origen = 'web';

-- Reservar desde la web: igual que antes, pero sin vencimiento
create or replace function expo_web_reservar(p_rut text, p_stand uuid) returns json
language plpgsql security definer set search_path = public as $$
declare
  s socios;
  st expo_stands;
  v_zona text;
  v_precio numeric;
  v_id uuid;
begin
  select * into s from socios
   where deleted_at is null and length(expo_rut_norm(p_rut)) >= 7 and expo_rut_norm(rut) = expo_rut_norm(p_rut)
   limit 1 for update;
  if s.id is null then return json_build_object('ok', false, 'error', 'no_socio'); end if;
  if coalesce(s.suspended, false) then return json_build_object('ok', false, 'error', 'suspendido'); end if;
  if expo_deuda_socio(s.id) > 0 then return json_build_object('ok', false, 'error', 'deuda'); end if;
  if exists (select 1 from expo_inscripciones where socio_id = s.id and deleted_at is null) then
    return json_build_object('ok', false, 'error', 'ya_tiene');
  end if;

  select zona into v_zona from expo_stands where socio_sugerido_id = s.id and deleted_at is null limit 1;
  select * into st from expo_stands where id = p_stand and deleted_at is null for update;
  if st.id is null then return json_build_object('ok', false, 'error', 'no_stand'); end if;
  if v_zona is null or st.zona is distinct from v_zona then return json_build_object('ok', false, 'error', 'otra_zona'); end if;
  if exists (select 1 from expo_inscripciones where stand_id = st.id and deleted_at is null) then
    return json_build_object('ok', false, 'error', 'ocupado');
  end if;
  v_precio := expo_precio_lista(st);
  if v_precio <= 0 then return json_build_object('ok', false, 'error', 'sin_precio'); end if;

  insert into expo_inscripciones (stand_id, socio_id, precio, created_by, origen)
  values (st.id, s.id, v_precio, 'Página web (socio)', 'web')
  returning id into v_id;

  return json_build_object('ok', true, 'id', v_id, 'codigo', st.codigo, 'zona', st.zona, 'precio', v_precio);
end $$;

grant execute on function expo_web_reservar(text, uuid) to anon, authenticated;
