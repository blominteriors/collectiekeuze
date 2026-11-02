-- Foto's per artikel en per zijde (voor, links, rechts, achter).
-- Bron: de app-data in de data repo (collectie/<leverancier>.json, veld zijden). De actie 'Data naar Supabase'
-- vervangt per leverancier alle rijen. De foto zelf staat in de opslag (bucket collectie) in het fotodeel 'bestand' onder sleutel 'img'.
create table if not exists public.artikel_fotos (
  leverancier text not null,
  artikel_id  text not null,
  zijde       text not null check (zijde in ('voor', 'links', 'rechts', 'achter')),
  herkomst    text,            -- exact (catalogus/prijslijst), web, base, other
  zekerheid   int,
  bron        text,            -- pagina of document waar de foto vandaan komt
  bestand     text,            -- fotodeel in de opslag, bv. infiniti-img-6.json
  img         int,             -- sleutel in dat fotodeel
  getoond     boolean not null default false,  -- deze zijde is de foto die de app laat zien
  bijgewerkt  timestamptz not null default now(),
  primary key (leverancier, artikel_id, zijde)
);

alter table public.artikel_fotos enable row level security;
drop policy if exists "artikel_fotos lezen voor Blom" on public.artikel_fotos;
create policy "artikel_fotos lezen voor Blom" on public.artikel_fotos
  for select to authenticated using ((select public.is_blom()));

-- Eén regel per artikel: welke zijden er zijn en welke de app toont
-- (volgorde voor, links, rechts, achter; een zijde telt mee vanaf zekerheid 90).
create or replace view public.artikel_fotos_overzicht
with (security_invoker = true) as
select leverancier,
       artikel_id,
       bool_or(zijde = 'voor')   as voor,
       bool_or(zijde = 'links')  as links,
       bool_or(zijde = 'rechts') as rechts,
       bool_or(zijde = 'achter') as achter,
       max(zijde) filter (where getoond) as getoonde_zijde,
       max(zekerheid) filter (where getoond) as zekerheid
from public.artikel_fotos
group by leverancier, artikel_id;
