-- Overzichtstabellen voor gebruik in Supabase zelf (Table editor), per versie.
-- De app blijft de bestanden in de versiebucket gebruiken; deze tabellen vult de actie 'Data naar Supabase'.

-- 1. Losse foto's met een link: openbare bucket 'fotos', pad <versie>/<leverancier>/<foto>.webp
insert into storage.buckets (id, name, public) values ('fotos', 'fotos', true)
on conflict (id) do update set public = true;

alter table public.artikel_fotos add column if not exists url text;

drop view if exists public.artikel_fotos_overzicht;
create view public.artikel_fotos_overzicht with (security_invoker = true) as
select versie, leverancier, artikel_id,
       max(url) filter (where zijde = 'voor')   as voor,
       max(url) filter (where zijde = 'links')  as links,
       max(url) filter (where zijde = 'rechts') as rechts,
       max(url) filter (where zijde = 'achter') as achter,
       max(zijde) filter (where getoond) as getoonde_zijde,
       max(zekerheid) filter (where getoond) as zekerheid
from public.artikel_fotos
group by versie, leverancier, artikel_id;

-- 2. Prijzen: per artikel en stofgroep een regel, uit de prijslijsten van de app
create table if not exists public.prijzen (
  versie            text not null references public.versies(naam),
  leverancier       text not null,
  nummer_leverancier text not null,
  regel             int  not null,
  stofgroep         text,
  blom_stofgroep    text,
  uitvoering        text,
  bruto             numeric,
  netto_inkoop      numeric,
  verrekenprijs     numeric,
  verkoopprijs      numeric,
  blom_care         numeric,
  prijslijst        text,
  bijgewerkt        timestamptz not null default now(),
  primary key (versie, leverancier, nummer_leverancier, regel)
);
alter table public.prijzen enable row level security;
drop policy if exists "Blom leest prijzen" on public.prijzen;
create policy "Blom leest prijzen" on public.prijzen
  for select to authenticated using ((select public.is_blom()));

-- 3. Collectie: per artikel wat de app toont, met de AFAS-status en de foto
create table if not exists public.collectie (
  versie            text not null references public.versies(naam),
  leverancier       text not null,
  artikel_id        text not null,
  serie             text,
  productcategorie  text,
  soort             text,
  nummer_leverancier text,
  afwerking         text,
  blom_naam         text,
  naamvoorstel      text,
  afas_nr           text,
  in_afas           boolean,
  online            boolean,
  zichtbaar_klanten boolean,
  hospitality       boolean,
  care              boolean,
  student_housing   boolean,
  leisure           boolean,
  smart_living      boolean,
  breedte_cm        numeric,
  diepte_cm         numeric,
  zithoogte_cm      numeric,
  hoogte_cm         numeric,
  foto              text,
  foto_zijde        text,
  foto_zekerheid    int,
  omschrijving      text,
  productpagina     text,
  bijgewerkt        timestamptz not null default now(),
  primary key (versie, leverancier, artikel_id)
);
alter table public.collectie enable row level security;
drop policy if exists "Blom leest collectie" on public.collectie;
create policy "Blom leest collectie" on public.collectie
  for select to authenticated using ((select public.is_blom()));

create or replace view public.collectie_in_afas with (security_invoker = true) as
  select * from public.collectie where in_afas;
