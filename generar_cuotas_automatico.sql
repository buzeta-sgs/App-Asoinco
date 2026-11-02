-- ASOINCO · Generación automática de la cuota mensual
-- Pegar COMPLETO en Supabase → SQL Editor → Run (se hace una sola vez).
--
-- Qué hace: el día 1 de cada mes crea la cuota de ese mes para todos los socios
-- activos que tengan valor de cuota. No duplica si la cuota ya existe.
-- No se crea para: socios suspendidos, eliminados, sin valor de cuota (cuota 0)
-- ni con fecha de término anterior al mes.

create extension if not exists pg_cron with schema extensions;

create or replace function generar_cuotas_mes(p_fecha date default (now() at time zone 'America/Santiago')::date)
returns integer
language plpgsql
security definer
as $$
declare
  v_mes date := date_trunc('month', p_fecha)::date;
  v_n integer;
  v_meses text[] := array['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
begin
  insert into cuotas (socio_id, invoice_number, amount, due_date, status)
  select s.id,
         'Cuota ' || v_meses[extract(month from v_mes)::int] || ' ' || extract(year from v_mes)::int,
         s.valor_cuota,
         v_mes,
         'pending'
  from socios s
  where s.deleted_at is null
    and coalesce(s.suspended, false) = false
    and coalesce(s.valor_cuota, 0) > 0
    and (s.fecha_termino is null or s.fecha_termino >= v_mes)
    and not exists (
      select 1 from cuotas c
      where c.socio_id = s.id
        and c.deleted_at is null
        and date_trunc('month', c.due_date)::date = v_mes
    );
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Programación: día 1 de cada mes a las 08:00 UTC (madrugada en Chile, siempre ya es día 1)
do $$
begin
  if exists (select 1 from cron.job where jobname = 'generar-cuotas-mes') then
    perform cron.unschedule('generar-cuotas-mes');
  end if;
end $$;

select cron.schedule('generar-cuotas-mes', '0 8 1 * *', $$select generar_cuotas_mes()$$);

-- Para revisar que quedó programado (opcional):
-- select jobname, schedule, active from cron.job;
--
-- Para generar OCTUBRE a mano, si hiciera falta (opcional):
-- select generar_cuotas_mes('2026-10-01');
