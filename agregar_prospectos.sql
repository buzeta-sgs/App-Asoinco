-- ASOINCO · Prospectos (empresas interesadas en ser socias)
-- Pegar completo en Supabase → SQL Editor → Run (una sola vez)

create table if not exists prospectos (
  id uuid primary key default gen_random_uuid(),
  empresa text not null,
  rut text,
  correo text,
  telefono text,
  direccion text,
  rubro text,
  representante text,
  rut_rep text,
  valor_cuota numeric not null default 25000,
  patrocinante1 text,
  patrocinante2 text,
  notas text,
  estado text not null default 'nuevo' check (estado in ('nuevo','carta_enviada','aceptado','rechazado')),
  carta_enviada_at timestamptz,
  contrato_enviado_at timestamptz,
  socio_id uuid references socios(id) on delete set null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

alter table prospectos enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename='prospectos' and policyname='prospectos_all') then
    create policy "prospectos_all" on prospectos for all using (true) with check (true);
  end if;
end $$;
