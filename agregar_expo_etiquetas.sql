-- ASOINCO · Etiquetas editables del encabezado de la Expo (los "chips" bajo el título)
-- Pegar completo en Supabase (proyecto ASOINCO) → SQL Editor → Run (una sola vez)
alter table expo_config add column if not exists chips jsonb;
