-- Leveranciersprijslijsten (bron/prijslijsten/*.xlsx), per versie (test, v1) en leverancier.
create table if not exists public.prijslijst_leveranciers (
  versie text not null,
  leverancier text not null,
  naam text,
  naam_in_prijslijst text,
  prijslijst_jaar integer,
  korting numeric,
  transporttoeslag numeric,
  opslag_verkoop numeric,
  opslag_care numeric,
  parameters jsonb,
  notities text,
  aantal_artikelen integer,
  aantal_dimensies integer,
  aantal_opties integer,
  bronbestand text,
  geladen_op timestamptz not null default now(),
  primary key (versie, leverancier)
);

create table if not exists public.prijslijst_artikelen (
  versie text not null,
  leverancier text not null,
  regel integer not null,
  afas_nr text,
  naam_leverancier text,
  nummer_leverancier text,
  blom_naam text,
  productgroep text,
  aantal_dimensies integer,
  omschrijving_leverancier text,
  uitvoering_leverancier text,
  care boolean,
  hospitality boolean,
  leisure boolean,
  student_housing boolean,
  smart_living boolean,
  in_online_collectie boolean,
  toegankelijk_klanten boolean,
  breedte_cm numeric,
  zitbreedte_cm numeric,
  diepte_cm numeric,
  zitdiepte_cm numeric,
  zithoogte_cm numeric,
  armleuninghoogte_cm numeric,
  hoogte_cm numeric,
  stofmetrage_1st_cm numeric,
  stofmetrage_2st_cm numeric,
  stofmetrage_extra_cm numeric,
  gewicht_kg numeric,
  prijslijst_bron text,
  opmerking text,
  extra jsonb,
  bronbestand text,
  geladen_op timestamptz not null default now(),
  primary key (versie, leverancier, regel)
);
create index if not exists prijslijst_artikelen_code_idx on public.prijslijst_artikelen (versie, leverancier, nummer_leverancier);
create index if not exists prijslijst_artikelen_afas_idx on public.prijslijst_artikelen (afas_nr);

create table if not exists public.prijslijst_dimensies (
  versie text not null,
  leverancier text not null,
  regel integer not null,
  afas_nr text,
  nummer_leverancier text,
  blom_naam text,
  stofcategorie_leverancier text,
  stofcategorie_blom text,
  uitvoering_frame text,
  uitvoering_afwerking text,
  uitvoering_brandvertragend text,
  uitvoering_lengte text,
  uitvoering_overig text,
  stofmetrage_m numeric,
  prijs_bruto numeric,
  netto_inkoop numeric,
  verrekenprijs numeric,
  verkoopprijs numeric,
  blom_care numeric,
  opmerking text,
  extra jsonb,
  bronbestand text,
  geladen_op timestamptz not null default now(),
  primary key (versie, leverancier, regel)
);
create index if not exists prijslijst_dimensies_code_idx on public.prijslijst_dimensies (versie, leverancier, nummer_leverancier);
create index if not exists prijslijst_dimensies_afas_idx on public.prijslijst_dimensies (afas_nr);

create table if not exists public.prijslijst_opties (
  versie text not null,
  leverancier text not null,
  regel integer not null,
  afas_nr text,
  nummer_leverancier text,
  uitvoering text,
  optiegroep text,
  optie text,
  code text,
  meerprijs numeric,
  bronbestand text,
  geladen_op timestamptz not null default now(),
  primary key (versie, leverancier, regel)
);
create index if not exists prijslijst_opties_code_idx on public.prijslijst_opties (versie, leverancier, nummer_leverancier);

alter table public.prijslijst_leveranciers enable row level security;
alter table public.prijslijst_artikelen enable row level security;
alter table public.prijslijst_dimensies enable row level security;
alter table public.prijslijst_opties enable row level security;

create policy "Blom leest prijslijst_leveranciers" on public.prijslijst_leveranciers for select to authenticated using ((select is_blom()));
create policy "Blom leest prijslijst_artikelen" on public.prijslijst_artikelen for select to authenticated using ((select is_blom()));
create policy "Blom leest prijslijst_dimensies" on public.prijslijst_dimensies for select to authenticated using ((select is_blom()));
create policy "Blom leest prijslijst_opties" on public.prijslijst_opties for select to authenticated using ((select is_blom()));

comment on table public.prijslijst_leveranciers is 'Per leverancier: korting, transporttoeslag, opslag en notities uit het tabblad Dimensies van de prijslijst';
comment on table public.prijslijst_artikelen is 'Tabblad Artikelen van de leveranciersprijslijsten (bron/prijslijsten)';
comment on table public.prijslijst_dimensies is 'Tabblad Dimensies: elke combinatie van stof en uitvoering met bruto, netto inkoop, verreken-, verkoop- en Care-prijs';
comment on table public.prijslijst_opties is 'Tabblad Opties (meerprijzen), alleen bij leveranciers die dat hebben';