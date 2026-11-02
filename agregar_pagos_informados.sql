-- ASOINCO · Expo: el socio informa su transferencia desde la página de reserva y adjunta el comprobante.
-- El comprobante queda en storage (cuotas/expo/comprobantes/<inscripcion>/) y el aviso aparece en la app,
-- donde ASOINCO lo confirma (se registra como pago) o lo rechaza.
-- Pegar COMPLETO en Supabase (proyecto ASOINCO) → SQL Editor → Run (una sola vez).

create table if not exists expo_pagos_informados (
  id uuid primary key default gen_random_uuid(),
  inscripcion_id uuid not null references expo_inscripciones(id) on delete cascade,
  monto numeric not null,
  fecha_pago date,
  banco text,
  nota text,
  comprobante_path text not null,
  estado text not null default 'pendiente' check (estado in ('pendiente', 'confirmado', 'rechazado')),
  pago_id uuid references expo_pagos(id) on delete set null,
  revisado_por text,
  revisado_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists expo_pagos_informados_insc on expo_pagos_informados(inscripcion_id);

alter table expo_pagos_informados enable row level security;
do $$
begin
  if not exists (select 1 from pg_policies where tablename='expo_pagos_informados' and policyname='expo_pagos_informados_all') then
    create policy "expo_pagos_informados_all" on expo_pagos_informados for all using (true) with check (true);
  end if;
end $$;

-- El socio informa su pago: se valida que el RUT sea el dueño de la reserva y que el archivo esté en su carpeta
create or replace function expo_web_informar_pago(p_rut text, p_inscripcion uuid, p_monto numeric, p_fecha date,
                                                   p_banco text, p_nota text, p_comprobante text) returns json
language plpgsql security definer set search_path = public as $$
declare
  i expo_inscripciones;
  s socios;
  v_id uuid;
begin
  select * into i from expo_inscripciones where id = p_inscripcion and deleted_at is null;
  if i.id is null then return json_build_object('ok', false, 'error', 'no_reserva'); end if;
  select * into s from socios where id = i.socio_id and deleted_at is null;
  if s.id is null or length(expo_rut_norm(p_rut)) < 7 or expo_rut_norm(s.rut) <> expo_rut_norm(p_rut) then
    return json_build_object('ok', false, 'error', 'no_reserva');
  end if;
  if p_monto is null or p_monto <= 0 then return json_build_object('ok', false, 'error', 'monto'); end if;
  if p_comprobante is null or p_comprobante not like 'expo/comprobantes/' || i.id::text || '/%' then
    return json_build_object('ok', false, 'error', 'archivo');
  end if;
  if (select count(*) from expo_pagos_informados where inscripcion_id = i.id and estado = 'pendiente') >= 5 then
    return json_build_object('ok', false, 'error', 'muchos');
  end if;

  insert into expo_pagos_informados (inscripcion_id, monto, fecha_pago, banco, nota, comprobante_path)
  values (i.id, round(p_monto), p_fecha, nullif(trim(p_banco), ''), nullif(trim(p_nota), ''), p_comprobante)
  returning id into v_id;
  return json_build_object('ok', true, 'id', v_id);
end $$;

-- Para que el socio vea en la página los pagos que ya informó y su estado
create or replace function expo_web_pagos_informados(p_rut text, p_inscripcion uuid) returns json
language plpgsql security definer set search_path = public as $$
declare
  i expo_inscripciones;
  s socios;
begin
  select * into i from expo_inscripciones where id = p_inscripcion and deleted_at is null;
  select * into s from socios where id = i.socio_id and deleted_at is null;
  if i.id is null or s.id is null or expo_rut_norm(s.rut) <> expo_rut_norm(p_rut) then return '[]'::json; end if;
  return coalesce((select json_agg(json_build_object('monto', monto, 'fecha_pago', fecha_pago, 'estado', estado, 'created_at', created_at)
                   order by created_at desc) from expo_pagos_informados where inscripcion_id = i.id), '[]'::json);
end $$;

grant execute on function expo_web_informar_pago(text, uuid, numeric, date, text, text, text) to anon, authenticated;
grant execute on function expo_web_pagos_informados(text, uuid) to anon, authenticated;
