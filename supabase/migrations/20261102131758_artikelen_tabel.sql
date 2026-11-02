-- Artikellijst uit de Excel in bron/, geladen door de synchronisatie in deze repository.
create table if not exists public.artikelen (
  rij bigint generated always as identity primary key,
  leverancier text,
  serie text,
  productcategorie text,
  soort text,
  product text,
  afwerking text,
  nummer_leverancier text,
  afas_nr text,
  blom_naam text,
  in_afas boolean,
  op_beeldbank boolean,
  toegankelijk_klanten boolean,
  hospitality boolean,
  care boolean,
  student_housing boolean,
  leisure boolean,
  smart_living boolean,
  naamvoorstel text,
  productkaart text,
  naam_controleren boolean,
  toelichting_naam text,
  breedte_cm numeric,
  zitbreedte_cm numeric,
  diepte_cm numeric,
  zitdiepte_cm numeric,
  zithoogte_cm numeric,
  armleuninghoogte_cm numeric,
  hoogte_cm numeric,
  maatreeks text,
  stofmetrage_m numeric,
  gewicht_kg numeric,
  omschrijving text,
  bron_omschrijving text,
  opties_en_meerprijzen text,
  opmerking_prijslijst text,
  prijslijst_bron text,
  foto_klopt_pct numeric,
  herkomst_foto text,
  productpagina text,
  vanaf_netto_inkoop numeric,
  vanaf_verrekenprijs numeric,
  vanaf_verkoopprijs numeric,
  vanaf_blom_care numeric,
  marge_eur numeric,
  marge_pct numeric,
  margestap_1_5 numeric,
  verkoop_blom_0_com numeric,
  verkoop_blom_1 numeric,
  verkoop_blom_2 numeric,
  verkoop_blom_3 numeric,
  verkoop_blom_4 numeric,
  verkoop_blom_5 numeric,
  verkoop_blom_6 numeric,
  verkoop_blom_7 numeric,
  verkoop_blom_8 numeric,
  verkoop_blom_9 numeric,
  verkoop_zonder_stofgroep numeric,
  prijsregels numeric,
  fout_in_excel text,
  bronbestand text,
  geladen_op timestamptz not null default now()
);
create index if not exists artikelen_leverancier_idx on public.artikelen (leverancier);
create index if not exists artikelen_afas_idx on public.artikelen (afas_nr);
alter table public.artikelen enable row level security;
drop policy if exists "Blom leest artikelen" on public.artikelen;
create policy "Blom leest artikelen" on public.artikelen
  for select to authenticated using ((select public.is_blom()));

-- Vervangt in één keer alle rijen van de leveranciers die in p_rijen voorkomen.
create or replace function public.artikelen_vervang(p_rijen jsonb, p_bron text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare n integer;
begin
  delete from public.artikelen
   where leverancier in (select distinct r->>'leverancier' from jsonb_array_elements(p_rijen) r);
  insert into public.artikelen (leverancier, serie, productcategorie, soort, product, afwerking, nummer_leverancier, afas_nr, blom_naam, in_afas, op_beeldbank, toegankelijk_klanten, hospitality, care, student_housing, leisure, smart_living, naamvoorstel, productkaart, naam_controleren, toelichting_naam, breedte_cm, zitbreedte_cm, diepte_cm, zitdiepte_cm, zithoogte_cm, armleuninghoogte_cm, hoogte_cm, maatreeks, stofmetrage_m, gewicht_kg, omschrijving, bron_omschrijving, opties_en_meerprijzen, opmerking_prijslijst, prijslijst_bron, foto_klopt_pct, herkomst_foto, productpagina, vanaf_netto_inkoop, vanaf_verrekenprijs, vanaf_verkoopprijs, vanaf_blom_care, marge_eur, marge_pct, margestap_1_5, verkoop_blom_0_com, verkoop_blom_1, verkoop_blom_2, verkoop_blom_3, verkoop_blom_4, verkoop_blom_5, verkoop_blom_6, verkoop_blom_7, verkoop_blom_8, verkoop_blom_9, verkoop_zonder_stofgroep, prijsregels, fout_in_excel, bronbestand)
  select x.leverancier, x.serie, x.productcategorie, x.soort, x.product, x.afwerking, x.nummer_leverancier, x.afas_nr, x.blom_naam, x.in_afas, x.op_beeldbank, x.toegankelijk_klanten, x.hospitality, x.care, x.student_housing, x.leisure, x.smart_living, x.naamvoorstel, x.productkaart, x.naam_controleren, x.toelichting_naam, x.breedte_cm, x.zitbreedte_cm, x.diepte_cm, x.zitdiepte_cm, x.zithoogte_cm, x.armleuninghoogte_cm, x.hoogte_cm, x.maatreeks, x.stofmetrage_m, x.gewicht_kg, x.omschrijving, x.bron_omschrijving, x.opties_en_meerprijzen, x.opmerking_prijslijst, x.prijslijst_bron, x.foto_klopt_pct, x.herkomst_foto, x.productpagina, x.vanaf_netto_inkoop, x.vanaf_verrekenprijs, x.vanaf_verkoopprijs, x.vanaf_blom_care, x.marge_eur, x.marge_pct, x.margestap_1_5, x.verkoop_blom_0_com, x.verkoop_blom_1, x.verkoop_blom_2, x.verkoop_blom_3, x.verkoop_blom_4, x.verkoop_blom_5, x.verkoop_blom_6, x.verkoop_blom_7, x.verkoop_blom_8, x.verkoop_blom_9, x.verkoop_zonder_stofgroep, x.prijsregels, x.fout_in_excel, p_bron
    from jsonb_populate_recordset(null::public.artikelen, p_rijen) x;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.artikelen_vervang(jsonb, text) from public, anon, authenticated;
grant execute on function public.artikelen_vervang(jsonb, text) to service_role;
