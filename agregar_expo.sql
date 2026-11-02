-- ASOINCO · Expo de stands (Feria Asoinco 2027)
-- Pegar completo en Supabase → SQL Editor → Run (una sola vez)

create table if not exists expo_config (
  id uuid primary key default gen_random_uuid(),
  nombre text not null default 'Feria Asoinco 2027',
  dias jsonb not null default '[
    {"n":1,"label":"Día 1","fecha":null},
    {"n":2,"label":"Día 2","fecha":null},
    {"n":3,"label":"Día 3","fecha":null},
    {"n":4,"label":"Día 4","fecha":null},
    {"n":5,"label":"Día 5","fecha":null}
  ]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists expo_stands (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  zona text,
  macrosector text,
  sugerido text,
  activo boolean not null default true,
  deleted_at timestamptz
);

create table if not exists expo_inscripciones (
  id uuid primary key default gen_random_uuid(),
  stand_id uuid not null references expo_stands(id) on delete cascade,
  socio_id uuid not null references socios(id) on delete cascade,
  precio numeric not null default 0,
  created_by text,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists expo_pagos (
  id uuid primary key default gen_random_uuid(),
  inscripcion_id uuid not null references expo_inscripciones(id) on delete cascade,
  amount numeric not null,
  payment_date date,
  bank text,
  created_by text,
  created_at timestamptz not null default now()
);

alter table expo_config enable row level security;
alter table expo_stands enable row level security;
alter table expo_inscripciones enable row level security;
alter table expo_pagos enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename='expo_config' and policyname='expo_config_all') then
    create policy "expo_config_all" on expo_config for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='expo_stands' and policyname='expo_stands_all') then
    create policy "expo_stands_all" on expo_stands for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='expo_inscripciones' and policyname='expo_inscripciones_all') then
    create policy "expo_inscripciones_all" on expo_inscripciones for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename='expo_pagos' and policyname='expo_pagos_all') then
    create policy "expo_pagos_all" on expo_pagos for all using (true) with check (true);
  end if;
end $$;

-- Configuración inicial (si no existe ninguna todavía)
insert into expo_config (nombre)
select 'Feria Asoinco 2027'
where not exists (select 1 from expo_config);

-- Nota: los 134 stands del plano (con zona, rubro y sugerencia de empresa) se cargan
-- aparte, desde la app, para que Claude pueda emparejar los nombres con tus socios reales.
