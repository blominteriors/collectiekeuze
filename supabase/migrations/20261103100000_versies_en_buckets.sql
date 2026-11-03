-- Eén project voor alle versies van de app (test, v1, v2 ...).
-- Bestanden staan per versie in een eigen bucket met dezelfde indeling:
--   collectie/<leverancier>.json, collectie/suppliers.json   artikelgegevens
--   afbeeldingen/<leverancier>/<leverancier>-img-N.json     foto's
--   prijzen/<leverancier>/<leverancier>.json (+ -1, -2 ...)  prijslijsten
--   gebruikers/                                             exports van de keuzes
--   algemeen/fonts/                                         lettertypes
-- Accounts zijn gedeeld; keuzes, artikelen en foto's hebben een kolom versie.

-- 1. Versiebeheer
create table if not exists public.versies (
  naam        text primary key,
  bucket      text not null unique,
  status      text not null check (status in ('test', 'live', 'archief')),
  omschrijving text,
  aangemaakt  timestamptz not null default now()
);
alter table public.versies enable row level security;
drop policy if exists "Blom leest versies" on public.versies;
create policy "Blom leest versies" on public.versies
  for select to authenticated using ((select public.is_blom()));

insert into public.versies (naam, bucket, status, omschrijving) values
  ('test', 'test', 'test', 'Testomgeving (tak ontwikkeling)'),
  ('v1',   'v1',   'live', 'Eerste live versie (tak main)')
on conflict (naam) do nothing;

-- 2. Buckets per versie, alleen leesbaar voor Blom
insert into storage.buckets (id, name, public) values ('test', 'test', false), ('v1', 'v1', false)
on conflict (id) do update set public = false;

drop policy if exists "Blom leest versiebuckets" on storage.objects;
create policy "Blom leest versiebuckets" on storage.objects
  for select to authenticated
  using (bucket_id in (select v.bucket from public.versies v) and (select public.is_blom()));

-- 3. Keuzes per versie
alter table public.keuzes add column if not exists versie text not null default 'v1' references public.versies(naam);
alter table public.keuzes drop constraint if exists keuzes_pkey;
alter table public.keuzes add primary key (versie, id);
create index if not exists keuzes_versie_sup_idx on public.keuzes (versie, sup);

drop function if exists public.keuze_zet(text, text, text, jsonb, boolean);
create or replace function public.keuze_zet(
  p_id text, p_sup text, p_naam text, p_c jsonb, p_vervang boolean default false, p_versie text default 'v1')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cur public.keuzes;
begin
  if not public.is_blom() then
    raise exception 'not_granted' using errcode = '42501';
  end if;
  if not exists (select 1 from public.versies where naam = p_versie and status <> 'archief') then
    raise exception 'onbekende of gearchiveerde versie %', p_versie using errcode = '22023';
  end if;
  select * into cur from public.keuzes where versie = p_versie and id = p_id for update;
  if not found then
    insert into public.keuzes (versie, id, sup, naam, c, laatst, user_id, bijgewerkt_door)
    values (p_versie, p_id, p_sup, p_naam, coalesce(p_c, '{}'::jsonb), now(), auth.uid(), auth.jwt() ->> 'email');
  else
    if cur.user_id is not null and cur.user_id <> auth.uid() then
      raise exception 'not_granted' using errcode = '42501';
    end if;
    update public.keuzes
       set naam = p_naam,
           sup  = p_sup,
           c    = case when p_vervang then coalesce(p_c, '{}'::jsonb) else c || coalesce(p_c, '{}'::jsonb) end,
           laatst = now(),
           user_id = coalesce(user_id, auth.uid()),
           bijgewerkt_door = auth.jwt() ->> 'email'
     where versie = p_versie and id = p_id;
  end if;
end;
$$;
revoke all on function public.keuze_zet(text, text, text, jsonb, boolean, text) from public, anon;
grant execute on function public.keuze_zet(text, text, text, jsonb, boolean, text) to authenticated;

create or replace view public.keuzes_test with (security_invoker = true) as
  select * from public.keuzes where versie = 'test';
create or replace view public.keuzes_v1 with (security_invoker = true) as
  select * from public.keuzes where versie = 'v1';

-- 4. Artikelen en foto's per versie
alter table public.artikelen add column if not exists versie text not null default 'v1' references public.versies(naam);
alter table public.artikel_fotos add column if not exists versie text not null default 'v1' references public.versies(naam);
alter table public.artikel_fotos drop constraint if exists artikel_fotos_pkey;
alter table public.artikel_fotos add primary key (versie, leverancier, artikel_id, zijde);
create index if not exists artikelen_versie_lev_idx on public.artikelen (versie, leverancier);

-- 5. Overzichten met versie als eerste kolom
drop view if exists public.keuzes_per_serie;
create view public.keuzes_per_serie with (security_invoker = true) as
SELECT k.versie,
    k.naam AS beoordelaar,
    CASE k.sup WHEN 'brees' THEN 'Bree''s New World' ELSE initcap(k.sup) END AS leverancier,
    initcap(replace(split_part(e.key, '~', 2), '-', ' ')) AS serie,
    CASE (e.value ->> 's') WHEN 'wel' THEN 'Houden' WHEN 'niet' THEN 'Niet houden' ELSE (e.value ->> 's') END AS keuze,
    CASE (e.value ->> 'oc') WHEN 'klant' THEN 'Online, voor klanten' WHEN 'intern' THEN 'Online, alleen intern' WHEN 'niet' THEN 'Niet online' ELSE NULL END AS online,
    NULLIF(concat_ws(', ',
        CASE WHEN ((e.value -> 'lab') ->> 0) = '1' THEN 'Hospitality' END,
        CASE WHEN ((e.value -> 'lab') ->> 1) = '1' THEN 'Care' END,
        CASE WHEN ((e.value -> 'lab') ->> 2) = '1' THEN 'Student housing' END,
        CASE WHEN ((e.value -> 'lab') ->> 3) = '1' THEN 'Leisure' END,
        CASE WHEN ((e.value -> 'lab') ->> 4) = '1' THEN 'Smart living' END), '') AS labels,
    (SELECT count(*) FROM jsonb_each(COALESCE(e.value -> 'v', '{}'::jsonb)) u(key, value) WHERE u.value::text = '1') AS uitvoeringen_houden,
    (SELECT count(*) FROM jsonb_each(COALESCE(e.value -> 'v', '{}'::jsonb)) u(key, value) WHERE u.value::text = '0') AS uitvoeringen_niet,
    (e.value ->> 't')::timestamptz AS gekozen_op,
    k.bijgewerkt_door AS account,
    e.key AS serie_code
FROM public.keuzes k CROSS JOIN LATERAL jsonb_each(k.c) e(key, value)
WHERE (e.value ->> 's') IS NOT NULL;

drop view if exists public.keuzes_per_uitvoering;
create view public.keuzes_per_uitvoering with (security_invoker = true) as
SELECT k.versie,
    k.naam AS beoordelaar,
    CASE k.sup WHEN 'brees' THEN 'Bree''s New World' ELSE initcap(k.sup) END AS leverancier,
    initcap(replace(split_part(e.key, '~', 2), '-', ' ')) AS serie,
    u.key AS nummer_leverancier,
    CASE WHEN u.value::text = '1' THEN 'Houden' ELSE 'Niet houden' END AS keuze,
    a.product, a.afas_nr, a.blom_naam,
    (e.value ->> 't')::timestamptz AS gekozen_op
FROM public.keuzes k
  CROSS JOIN LATERAL jsonb_each(k.c) e(key, value)
  CROSS JOIN LATERAL jsonb_each(COALESCE(e.value -> 'v', '{}'::jsonb)) u(key, value)
  LEFT JOIN LATERAL (
    SELECT ar.product, ar.afas_nr, ar.blom_naam FROM public.artikelen ar
    WHERE ar.versie = k.versie AND ar.nummer_leverancier = u.key
      AND lower(ar.leverancier) LIKE CASE k.sup WHEN 'brees' THEN 'bree%' ELSE k.sup || '%' END
    ORDER BY ar.afas_nr LIMIT 1) a ON true
WHERE (e.value ->> 's') = 'wel';

drop view if exists public.artikel_fotos_overzicht;
create view public.artikel_fotos_overzicht with (security_invoker = true) as
SELECT versie, leverancier, artikel_id,
    bool_or(zijde = 'voor') AS voor,
    bool_or(zijde = 'links') AS links,
    bool_or(zijde = 'rechts') AS rechts,
    bool_or(zijde = 'achter') AS achter,
    max(zijde) FILTER (WHERE getoond) AS getoonde_zijde,
    max(zekerheid) FILTER (WHERE getoond) AS zekerheid
FROM public.artikel_fotos
GROUP BY versie, leverancier, artikel_id;

-- 6. Artikelen laden per versie
drop function if exists public.artikelen_vervang(jsonb, text);
create or replace function public.artikelen_vervang(p_rijen jsonb, p_bron text, p_versie text default 'v1')
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  delete from public.artikelen
   where versie = p_versie and leverancier in (select distinct r->>'leverancier' from jsonb_array_elements(p_rijen) r);
  insert into public.artikelen (versie, leverancier, serie, productcategorie, soort, product, afwerking, nummer_leverancier, afas_nr, blom_naam, in_afas, op_beeldbank, toegankelijk_klanten, hospitality, care, student_housing, leisure, smart_living, naamvoorstel, productkaart, naam_controleren, toelichting_naam, breedte_cm, zitbreedte_cm, diepte_cm, zitdiepte_cm, zithoogte_cm, armleuninghoogte_cm, hoogte_cm, maatreeks, stofmetrage_m, gewicht_kg, omschrijving, bron_omschrijving, opties_en_meerprijzen, opmerking_prijslijst, prijslijst_bron, foto_klopt_pct, herkomst_foto, productpagina, vanaf_netto_inkoop, vanaf_verrekenprijs, vanaf_verkoopprijs, vanaf_blom_care, marge_eur, marge_pct, margestap_1_5, verkoop_blom_0_com, verkoop_blom_1, verkoop_blom_2, verkoop_blom_3, verkoop_blom_4, verkoop_blom_5, verkoop_blom_6, verkoop_blom_7, verkoop_blom_8, verkoop_blom_9, verkoop_zonder_stofgroep, prijsregels, fout_in_excel, bronbestand)
  select p_versie, x.leverancier, x.serie, x.productcategorie, x.soort, x.product, x.afwerking, x.nummer_leverancier, x.afas_nr, x.blom_naam, x.in_afas, x.op_beeldbank, x.toegankelijk_klanten, x.hospitality, x.care, x.student_housing, x.leisure, x.smart_living, x.naamvoorstel, x.productkaart, x.naam_controleren, x.toelichting_naam, x.breedte_cm, x.zitbreedte_cm, x.diepte_cm, x.zitdiepte_cm, x.zithoogte_cm, x.armleuninghoogte_cm, x.hoogte_cm, x.maatreeks, x.stofmetrage_m, x.gewicht_kg, x.omschrijving, x.bron_omschrijving, x.opties_en_meerprijzen, x.opmerking_prijslijst, x.prijslijst_bron, x.foto_klopt_pct, x.herkomst_foto, x.productpagina, x.vanaf_netto_inkoop, x.vanaf_verrekenprijs, x.vanaf_verkoopprijs, x.vanaf_blom_care, x.marge_eur, x.marge_pct, x.margestap_1_5, x.verkoop_blom_0_com, x.verkoop_blom_1, x.verkoop_blom_2, x.verkoop_blom_3, x.verkoop_blom_4, x.verkoop_blom_5, x.verkoop_blom_6, x.verkoop_blom_7, x.verkoop_blom_8, x.verkoop_blom_9, x.verkoop_zonder_stofgroep, x.prijsregels, x.fout_in_excel, p_bron
    from jsonb_populate_recordset(null::public.artikelen, p_rijen) x;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.artikelen_vervang(jsonb, text, text) from public, anon, authenticated;
grant execute on function public.artikelen_vervang(jsonb, text, text) to service_role;
