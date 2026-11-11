create schema if not exists collectie;
comment on schema collectie is 'Collectiegegevens van Blom (namenlijst Blomnamen)';

create table collectie.blom_namen (
  id bigint generated always as identity primary key,
  versie text not null default 'v1',
  naam text not null,
  land text not null,
  status text not null default 'vrij' check (status in ('vrij','gereserveerd','in gebruik')),
  leverancier text,
  leveranciersnaam text,
  afas_nr text,
  bron text,
  opmerking text,
  bijgewerkt_op timestamptz not null default now(),
  bijgewerkt_door text
);
create index blom_namen_naam_idx on collectie.blom_namen (lower(naam));
create index blom_namen_land_idx on collectie.blom_namen (land, status);
comment on table collectie.blom_namen is 'Blom-artikelnamenlijst (wereldsteden). Leidend sinds 3-11-2026: Blomnamen alleen hieruit kiezen en hier direct bijwerken.';

create table collectie.blom_namen_leveranciers (
  versie text not null default 'v1',
  leverancier text not null,
  toegewezen_land text,
  bijgewerkt_op timestamptz not null default now(),
  primary key (versie, leverancier)
);
comment on table collectie.blom_namen_leveranciers is 'Welk land (namenreeks) bij welke leverancier hoort, uit de Blom-artikelnamenlijst.';

alter table collectie.blom_namen enable row level security;
alter table collectie.blom_namen_leveranciers enable row level security;
create policy "Blom leest blom_namen" on collectie.blom_namen for select to authenticated using ((select public.is_blom()));
create policy "Blom leest blom_namen_leveranciers" on collectie.blom_namen_leveranciers for select to authenticated using ((select public.is_blom()));
grant usage on schema collectie to authenticated, service_role;
grant select on all tables in schema collectie to authenticated;
grant all on all tables in schema collectie to service_role;