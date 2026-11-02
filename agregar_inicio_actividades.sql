-- Fecha de inicio de actividades del prospecto (sale en la carta de interés)
alter table prospectos add column if not exists inicio_actividades date;
notify pgrst, 'reload schema';
