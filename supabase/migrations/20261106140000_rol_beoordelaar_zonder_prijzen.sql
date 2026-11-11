-- Nieuwe rol: beoordelaar zonder prijzen.
--   beoordelaar_zonder_prijzen : als beoordelaar (eigen keuzes, elke leverancier één keer), maar ziet geen prijzen.
-- De app toont deze rol geen prijzen; de prijslijsten in de opslag en de tabel prijzen zijn voor deze rol ook niet leesbaar.

-- 1. de rol toestaan in de gebruikerslijst
alter table app.gebruikers drop constraint if exists gebruikers_rol_check;
alter table app.gebruikers add constraint gebruikers_rol_check
  check (rol in ('beheerder', 'beoordelaar', 'beoordelaar_zonder_prijzen'));

create or replace function public.gebruiker_zet(p_email text, p_naam text, p_rol text)
returns void language plpgsql security definer set search_path = ''
as $$
declare e text := lower(btrim(p_email));
begin
  if not public.is_beheerder() then raise exception 'not_granted' using errcode = '42501'; end if;
  if e not like '%_@blominterieurs.nl' then raise exception 'Alleen @blominterieurs.nl-adressen' using errcode = '22023'; end if;
  if p_rol not in ('beheerder', 'beoordelaar', 'beoordelaar_zonder_prijzen') then raise exception 'Onbekende rol %', p_rol using errcode = '22023'; end if;
  if p_rol <> 'beheerder' and exists (select 1 from app.gebruikers where email = e and rol = 'beheerder')
     and (select count(*) from app.gebruikers where rol = 'beheerder') <= 1 then
    raise exception 'Er moet minstens één beheerder blijven' using errcode = '22023';
  end if;
  insert into app.gebruikers (email, naam, rol, toegevoegd_door)
  values (e, nullif(btrim(p_naam), ''), p_rol, auth.jwt() ->> 'email')
  on conflict (email) do update set naam = coalesce(nullif(btrim(p_naam), ''), app.gebruikers.naam), rol = excluded.rol;
end $$;

-- 2. wie mag prijzen zien: iedereen met toegang, behalve de beoordelaar zonder prijzen
create or replace function public.mag_prijzen()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(public.mijn_rol_tekst() in ('beheerder', 'beoordelaar'), false) $$;

-- 3. prijslijsten in de versiebuckets (map prijzen/) alleen voor wie prijzen mag zien
drop policy if exists "Blom leest versiebuckets" on storage.objects;
create policy "Blom leest versiebuckets" on storage.objects
  for select to authenticated
  using (
    bucket_id in (select v.bucket from public.versies v)
    and (select public.is_blom())
    and ((storage.foldername(name))[1] is distinct from 'prijzen' or (select public.mag_prijzen()))
  );

-- 4. tabel prijzen alleen voor wie prijzen mag zien (de tabel staat in schema collectie; public.prijzen is een view daarop)
drop policy if exists "Blom leest prijzen" on collectie.prijzen;
create policy "Blom leest prijzen" on collectie.prijzen
  for select to authenticated using ((select public.mag_prijzen()));

-- 5. brandvertragend staat in de prijslijst (kolom uitvoering). Deze functie geeft alleen artikelnummer en uitvoering,
--    zonder bedragen, zodat ook de beoordelaar zonder prijzen het label Brandvertragend ziet.
create or replace function public.brandvertragend_regels(p_versie text, p_leverancier text)
returns table (nummer_leverancier text, uitvoering text)
language sql stable security definer set search_path = ''
as $$
  select distinct p.nummer_leverancier, p.uitvoering
  from collectie.prijzen p
  where public.is_blom()
    and p.versie = p_versie and p.leverancier = p_leverancier
    and p.uitvoering ilike '%brandvertr%'
  order by 1, 2
$$;

revoke all on function public.mag_prijzen(), public.brandvertragend_regels(text, text) from public, anon;
grant execute on function public.mag_prijzen(), public.brandvertragend_regels(text, text) to authenticated;
