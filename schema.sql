-- Esquema ASOINCO · Gestión de Socios y Cuotas
-- Ejecutar completo en Supabase SQL Editor (proyecto nuevo)

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'administrativa' check (role in ('presidente','gerente','administrativa')),
  last_login timestamptz
);

create table if not exists socios (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  rut text,
  contact_email text,
  representante text,
  telefono text,
  descripcion text,
  direccion text,
  tamano text,
  valor_cuota numeric,
  fecha_ingreso date,
  fecha_termino date,
  suspended boolean not null default false,
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists cuotas (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid not null references socios(id) on delete cascade,
  invoice_number text,
  amount numeric not null,
  due_date date,
  status text not null default 'pending' check (status in ('pending','paid')),
  created_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists cuota_abonos (
  id uuid primary key default gen_random_uuid(),
  cuota_id uuid not null references cuotas(id) on delete cascade,
  amount numeric not null,
  note text,
  payment_date date,
  bank text,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists cuota_documentos (
  id uuid primary key default gen_random_uuid(),
  cuota_id uuid not null references cuotas(id) on delete cascade,
  file_name text,
  file_url text,
  file_size bigint,
  uploaded_by text,
  uploaded_at timestamptz not null default now()
);

create table if not exists eventos (
  id uuid primary key default gen_random_uuid(),
  fecha date not null,
  titulo text not null,
  descripcion text,
  created_by text,
  created_at timestamptz not null default now()
);
alter table eventos enable row level security;
create policy "eventos_all" on eventos for all using (true) with check (true);

create table if not exists message_log (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid references socios(id) on delete set null,
  sent_to text,
  total_amount numeric,
  invoice_count integer,
  sent_by text,
  created_at timestamptz not null default now()
);

-- RLS: permisiva para usuarios autenticados (todos los roles pueden leer/escribir;
-- los límites de "administrativa" se controlan en la app, no aquí)
alter table profiles enable row level security;
alter table socios enable row level security;
alter table cuotas enable row level security;
alter table cuota_abonos enable row level security;
alter table cuota_documentos enable row level security;
alter table message_log enable row level security;

-- Nota: la app llama a la API REST solo con la llave pública (anon), no reenvía
-- el token del usuario logueado, así que las políticas deben ser permisivas aquí;
-- el control de quién puede hacer qué se hace dentro de la app (roles).
create policy "profiles_all" on profiles for all using (true) with check (true);
create policy "socios_all" on socios for all using (true) with check (true);
create policy "cuotas_all" on cuotas for all using (true) with check (true);
create policy "cuota_abonos_all" on cuota_abonos for all using (true) with check (true);
create policy "cuota_documentos_all" on cuota_documentos for all using (true) with check (true);
create policy "message_log_all" on message_log for all using (true) with check (true);

-- Storage: bucket público "cuotas" para adjuntos (documentos de cuotas, mensajes)
insert into storage.buckets (id, name, public)
values ('cuotas', 'cuotas', true)
on conflict (id) do nothing;

create policy "cuotas_bucket_read" on storage.objects for select using (bucket_id = 'cuotas');
create policy "cuotas_bucket_write" on storage.objects for insert with check (bucket_id = 'cuotas');

-- Trigger: crea automáticamente un profile cuando se crea un usuario en Auth
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, new.raw_user_meta_data->>'full_name', coalesce(new.raw_user_meta_data->>'role', 'administrativa'))
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
