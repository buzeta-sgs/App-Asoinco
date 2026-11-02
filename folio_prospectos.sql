-- ASOINCO · Folio fijo para cada prospecto
-- El folio se reserva al generar la carta de interés y es el MISMO en la carta, el contrato y la ficha del socio.
-- Pegar completo en Supabase → SQL Editor → Run (una sola vez)

alter table prospectos add column if not exists folio integer unique;

-- Toma el siguiente número de la misma numeración de los socios (nadie más puede usarlo)
create or replace function reservar_folio_prospecto(p_id uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare f integer;
begin
  select folio into f from prospectos where id = p_id for update;
  if f is null then
    f := nextval('socios_folio_seq');
    update prospectos set folio = f where id = p_id;
  end if;
  return f;
end $$;

grant execute on function reservar_folio_prospecto(uuid) to anon, authenticated;
notify pgrst, 'reload schema';
