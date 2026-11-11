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