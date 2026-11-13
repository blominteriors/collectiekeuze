-- Regels 3.1 (13 november 2026): plekken Schuin en Overig, overzicht per artikel, opschonen. Alleen toevoegen.
-- Toegepast op Database V1 op 13 november 2026 onder de naam regels_v31_schuin_overig_overzicht.
-- Versienummer gelijk aan supabase_migrations.schema_migrations (gecontroleerd op 13 november 2026).
-- Vooraf gemaakt (buiten deze migratie): backup.artikel_fotos_brees_test_20261113 en backup.collectie_brees_test_20261113.

-- 1. Extra gegevens per zijdefoto (regel J)
alter table collectie.artikel_fotos
  add column if not exists origineel_breedte_px integer,
  add column if not exists origineel_hoogte_px integer,
  add column if not exists vrijstaand boolean,
  add column if not exists origineel_url text;

-- 2. Uitvoering mag ook bevestigd zijn met beeldvergelijking of omschrijving (regels C1b en C1c)
alter table collectie.artikel_fotos drop constraint artikel_fotos_uitvoering_bevestigd_check;
alter table collectie.artikel_fotos add constraint artikel_fotos_uitvoering_bevestigd_check
  check (uitvoering_bevestigd = any (array['artikelnummer','maten','beeld','omschrijving']));
alter table collectie.foto_beoordelingen drop constraint foto_beoordelingen_uitvoering_bevestigd_check;
alter table collectie.foto_beoordelingen add constraint foto_beoordelingen_uitvoering_bevestigd_check
  check (uitvoering_bevestigd = any (array['artikelnummer','maten','beeld','omschrijving']));

-- 3. De weergave in public krijgt de nieuwe kolommen achteraan
create or replace view public.artikel_fotos with (security_invoker = true) as
 select leverancier, artikel_id, zijde, herkomst, zekerheid, bron, bestand, img, getoond, bijgewerkt, versie, url, blom_naam, afas_nr,
        breedte_px, hoogte_px, kwaliteit_rang, beeld_hash, aanzicht, niveau, uitvoering_bevestigd, bron_url, pagina_url, bron_soort,
        beschermd, regelversie, beoordeling_id, origineel_breedte_px, origineel_hoogte_px, vrijstaand, origineel_url
   from collectie.artikel_fotos;

-- 4. Schuin en Overig: meer foto's per artikel (regels I en I-b)
create table collectie.artikel_fotos_overig (
  versie text not null references public.versies(naam),
  leverancier text not null,
  artikel_id text not null,
  volgnr integer not null,
  plek text not null check (plek = any (array['schuin','overig'])),
  label text not null,
  soort text,
  url text not null,
  bestand text,
  bron_url text,
  pagina_url text,
  bron_soort text check (bron_soort = any (array['leverancier','dealer','overig','blom'])),
  herkomst text,
  breedte_px integer,
  hoogte_px integer,
  beeld_hash text,
  uitvoering_bevestigd text check (uitvoering_bevestigd = any (array['artikelnummer','maten','beeld','omschrijving'])),
  regelversie text,
  run text,
  bijgewerkt timestamptz not null default now(),
  primary key (versie, leverancier, artikel_id, volgnr)
);
create index artikel_fotos_overig_plek_idx on collectie.artikel_fotos_overig (versie, leverancier, artikel_id, plek);
alter table collectie.artikel_fotos_overig enable row level security;
create policy "artikel_fotos_overig lezen voor Blom" on collectie.artikel_fotos_overig
  for select to authenticated using ((select public.is_blom()));
revoke all on collectie.artikel_fotos_overig from anon, authenticated;
grant select on collectie.artikel_fotos_overig to authenticated;
grant all on collectie.artikel_fotos_overig to service_role;

create view public.artikel_fotos_overig with (security_invoker = true) as
 select * from collectie.artikel_fotos_overig;
revoke all on public.artikel_fotos_overig from anon, authenticated;
grant select on public.artikel_fotos_overig to authenticated;
grant all on public.artikel_fotos_overig to service_role;

-- 5. Overzicht per artikel: leverancier, zijden, aantal zijden compleet, schuin, overig en pixels per foto
create view public.artikel_fotos_per_artikel with (security_invoker = true) as
 select c.versie, c.leverancier, c.artikel_id, c.blom_naam, c.afas_nr, c.serie, c.soort,
        max(f.url) filter (where f.zijde = 'voor') as voor,
        max(f.url) filter (where f.zijde = 'links') as links,
        max(f.url) filter (where f.zijde = 'rechts') as rechts,
        max(f.url) filter (where f.zijde = 'achter') as achter,
        max(coalesce(f.origineel_breedte_px, f.breedte_px) || ' x ' || coalesce(f.origineel_hoogte_px, f.hoogte_px)) filter (where f.zijde = 'voor') as voor_px,
        max(coalesce(f.origineel_breedte_px, f.breedte_px) || ' x ' || coalesce(f.origineel_hoogte_px, f.hoogte_px)) filter (where f.zijde = 'links') as links_px,
        max(coalesce(f.origineel_breedte_px, f.breedte_px) || ' x ' || coalesce(f.origineel_hoogte_px, f.hoogte_px)) filter (where f.zijde = 'rechts') as rechts_px,
        max(coalesce(f.origineel_breedte_px, f.breedte_px) || ' x ' || coalesce(f.origineel_hoogte_px, f.hoogte_px)) filter (where f.zijde = 'achter') as achter_px,
        count(f.zijde) as zijden_compleet,
        (select count(*) from collectie.artikel_fotos_overig o
          where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'schuin') as aantal_schuin,
        (select count(*) from collectie.artikel_fotos_overig o
          where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'overig') as aantal_overig,
        min(greatest(coalesce(f.origineel_breedte_px, f.breedte_px), coalesce(f.origineel_hoogte_px, f.hoogte_px))) as kleinste_px
   from collectie.collectie c
   left join collectie.artikel_fotos f
     on f.versie = c.versie and f.leverancier = c.leverancier and f.artikel_id = c.artikel_id
  group by c.versie, c.leverancier, c.artikel_id, c.blom_naam, c.afas_nr, c.serie, c.soort;
revoke all on public.artikel_fotos_per_artikel from anon, authenticated;
grant select on public.artikel_fotos_per_artikel to authenticated;
grant all on public.artikel_fotos_per_artikel to service_role;
