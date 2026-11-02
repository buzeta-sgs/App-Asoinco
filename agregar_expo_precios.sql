-- ASOINCO · Precios de stands de la Expo (por zona y, si hace falta, por stand)
-- Pegar completo en Supabase (proyecto ASOINCO) → SQL Editor → Run (una sola vez)
alter table expo_config add column if not exists precios_zona jsonb;
alter table expo_stands add column if not exists precio numeric;
