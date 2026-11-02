-- ASOINCO · Expo: permitir que socios con cuotas pendientes reserven stand
-- (interruptor "exigir_al_dia" en Configurar; por defecto APAGADO = pueden reservar todos, salvo suspendidos)
-- Pegar COMPLETO en Supabase (proyecto ASOINCO) → SQL Editor → Run (una sola vez).

alter table expo_config add column if not exists exigir_al_dia boolean not null default false;

create or replace function expo_exige_al_dia() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select exigir_al_dia from expo_config order by created_at desc limit 1), false)
$$;

create or replace function expo_web_socio(p_rut text) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  s socios;
  v_zona text;
  v_rubro text;
  v_res json;
begin
  if length(expo_rut_norm(p_rut)) < 7 then
    return json_build_object('ok', false, 'error', 'rut_invalido');
  end if;
  select * into s from socios
   where deleted_at is null and expo_rut_norm(rut) = expo_rut_norm(p_rut)
   limit 1;
  if s.id is null then return json_build_object('ok', false, 'error', 'no_socio'); end if;
  if coalesce(s.suspended, false) then return json_build_object('ok', false, 'error', 'suspendido', 'nombre', s.name); end if;

  select json_build_object('id', i.id, 'codigo', st.codigo, 'zona', st.zona, 'precio', i.precio,
                           'pagado', coalesce((select sum(p.amount) from expo_pagos p where p.inscripcion_id = i.id), 0),
                           'vence_at', i.vence_at, 'comprobante_at', i.comprobante_at)
    into v_res
    from expo_inscripciones i join expo_stands st on st.id = i.stand_id
   where i.socio_id = s.id and i.deleted_at is null
   limit 1;

  select zona, macrosector into v_zona, v_rubro
    from expo_stands where socio_sugerido_id = s.id and deleted_at is null limit 1;

  if v_res is not null then
    return json_build_object('ok', true, 'nombre', s.name, 'zona', coalesce(v_zona, v_res ->> 'zona'), 'rubro', v_rubro, 'reserva', v_res);
  end if;

  if expo_exige_al_dia() and expo_deuda_socio(s.id) > 0 then
    return json_build_object('ok', false, 'error', 'deuda', 'nombre', s.name);
  end if;
  if v_zona is null then return json_build_object('ok', false, 'error', 'sin_zona', 'nombre', s.name); end if;

  return json_build_object(
    'ok', true, 'nombre', s.name, 'zona', v_zona, 'rubro', v_rubro, 'reserva', null,
    'stands', (
      select coalesce(json_agg(json_build_object(
               'id', st.id, 'codigo', st.codigo, 'precio', expo_precio_lista(st),
               'ocupado', exists (select 1 from expo_inscripciones i where i.stand_id = st.id and i.deleted_at is null),
               'sugerido', st.socio_sugerido_id = s.id)
             order by nullif(regexp_replace(st.codigo, '\D', '', 'g'), '')::int nulls last, st.codigo), '[]'::json)
      from expo_stands st
      where st.deleted_at is null and coalesce(st.activo, true) and st.zona = v_zona));
end $$;

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
  if expo_exige_al_dia() and expo_deuda_socio(s.id) > 0 then return json_build_object('ok', false, 'error', 'deuda'); end if;
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

grant execute on function expo_web_socio(text) to anon, authenticated;
grant execute on function expo_web_reservar(text, uuid) to anon, authenticated;
