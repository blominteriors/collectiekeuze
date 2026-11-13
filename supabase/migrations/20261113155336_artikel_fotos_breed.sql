-- Brede weergave: één rij per artikel, alle zijden naast elkaar, plus de eerste drie foto's van Schuin en Overig.
-- Alleen een weergave erbij; de tabel artikel_fotos (één rij per artikel en zijde) blijft zoals hij is.
-- Toegepast op Database V1 op 13 november 2026.
create view public.artikel_fotos_breed with (security_invoker = true) as
 with f as (
   select a.versie, a.leverancier, a.artikel_id, a.zijde, a.url, a.aanzicht, a.niveau,
          coalesce(a.origineel_breedte_px, a.breedte_px) || ' x ' || coalesce(a.origineel_hoogte_px, a.hoogte_px) as px,
          greatest(coalesce(a.origineel_breedte_px, a.breedte_px), coalesce(a.origineel_hoogte_px, a.hoogte_px)) as langste,
          case when a.vrijstaand then 'ja' when a.vrijstaand is false then 'nee' end as vrijstaand,
          case when b.oordeel ->> 'uitsnede' = 'true' then 'site, uitsnede'
               when a.herkomst = 'web' and a.bron_soort = 'leverancier' then 'site leverancier'
               when a.herkomst = 'web' and a.bron_soort = 'dealer' then 'dealer'
               when a.herkomst = 'web' then 'internet'
               when a.herkomst = 'exact' then 'prijslijst'
               when a.herkomst = 'bekl' then 'zelfde model, andere bekleding'
               when a.herkomst in ('base', 'model') then 'modelfoto'
               else a.herkomst end as bron
     from collectie.artikel_fotos a
     left join collectie.foto_beoordelingen b on b.id = a.beoordeling_id
 )
 select c.versie, c.leverancier, c.artikel_id, c.blom_naam, c.afas_nr, c.serie, c.soort,
        count(f.zijde) as zijden_compleet,
        (select count(*) from collectie.artikel_fotos_overig o where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'schuin') as aantal_schuin,
        (select count(*) from collectie.artikel_fotos_overig o where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'overig') as aantal_overig,
        min(f.langste) as kleinste_px,
        max(f.url) filter (where f.zijde = 'voor') as voor_foto,
        max(f.px) filter (where f.zijde = 'voor') as voor_px,
        max(f.aanzicht) filter (where f.zijde = 'voor') as voor_aanzicht,
        max(f.vrijstaand) filter (where f.zijde = 'voor') as voor_vrijstaand,
        max(f.niveau) filter (where f.zijde = 'voor') as voor_niveau,
        max(f.bron) filter (where f.zijde = 'voor') as voor_bron,
        max(f.url) filter (where f.zijde = 'links') as links_foto,
        max(f.px) filter (where f.zijde = 'links') as links_px,
        max(f.aanzicht) filter (where f.zijde = 'links') as links_aanzicht,
        max(f.vrijstaand) filter (where f.zijde = 'links') as links_vrijstaand,
        max(f.niveau) filter (where f.zijde = 'links') as links_niveau,
        max(f.bron) filter (where f.zijde = 'links') as links_bron,
        max(f.url) filter (where f.zijde = 'rechts') as rechts_foto,
        max(f.px) filter (where f.zijde = 'rechts') as rechts_px,
        max(f.aanzicht) filter (where f.zijde = 'rechts') as rechts_aanzicht,
        max(f.vrijstaand) filter (where f.zijde = 'rechts') as rechts_vrijstaand,
        max(f.niveau) filter (where f.zijde = 'rechts') as rechts_niveau,
        max(f.bron) filter (where f.zijde = 'rechts') as rechts_bron,
        max(f.url) filter (where f.zijde = 'achter') as achter_foto,
        max(f.px) filter (where f.zijde = 'achter') as achter_px,
        max(f.aanzicht) filter (where f.zijde = 'achter') as achter_aanzicht,
        max(f.vrijstaand) filter (where f.zijde = 'achter') as achter_vrijstaand,
        max(f.niveau) filter (where f.zijde = 'achter') as achter_niveau,
        max(f.bron) filter (where f.zijde = 'achter') as achter_bron,
        (select o.url from collectie.artikel_fotos_overig o where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'schuin' order by o.volgnr offset 0 limit 1) as schuin_1,
        (select o.url from collectie.artikel_fotos_overig o where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'schuin' order by o.volgnr offset 1 limit 1) as schuin_2,
        (select o.url from collectie.artikel_fotos_overig o where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'schuin' order by o.volgnr offset 2 limit 1) as schuin_3,
        (select o.url from collectie.artikel_fotos_overig o where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'overig' order by o.volgnr offset 0 limit 1) as overig_1,
        (select o.url from collectie.artikel_fotos_overig o where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'overig' order by o.volgnr offset 1 limit 1) as overig_2,
        (select o.url from collectie.artikel_fotos_overig o where o.versie = c.versie and o.leverancier = c.leverancier and o.artikel_id = c.artikel_id and o.plek = 'overig' order by o.volgnr offset 2 limit 1) as overig_3
   from collectie.collectie c
   left join f on f.versie = c.versie and f.leverancier = c.leverancier and f.artikel_id = c.artikel_id
  group by c.versie, c.leverancier, c.artikel_id, c.blom_naam, c.afas_nr, c.serie, c.soort;
revoke all on public.artikel_fotos_breed from anon, authenticated;
grant select on public.artikel_fotos_breed to authenticated;
grant all on public.artikel_fotos_breed to service_role;
