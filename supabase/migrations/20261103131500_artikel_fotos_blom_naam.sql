-- Blom-naam en AFAS-nummer bij de foto's, en in het overzicht per artikel.
alter table public.artikel_fotos add column if not exists blom_naam text;
alter table public.artikel_fotos add column if not exists afas_nr text;
drop view if exists public.artikel_fotos_overzicht;
create view public.artikel_fotos_overzicht with (security_invoker = true) as
select versie, leverancier, artikel_id, max(blom_naam) as blom_naam, max(afas_nr) as afas_nr,
       max(url) filter (where zijde = 'voor') as voor, max(url) filter (where zijde = 'links') as links,
       max(url) filter (where zijde = 'rechts') as rechts, max(url) filter (where zijde = 'achter') as achter,
       max(zijde) filter (where getoond) as getoonde_zijde, max(zekerheid) filter (where getoond) as zekerheid
from public.artikel_fotos group by versie, leverancier, artikel_id;
