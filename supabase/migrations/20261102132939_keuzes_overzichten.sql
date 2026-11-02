-- Leesbare overzichten van de keuzes voor gebruik buiten de app. security_invoker: zelfde afscherming als keuzes.
create or replace view public.keuzes_per_serie
with (security_invoker = true) as
select
  k.naam                                            as beoordelaar,
  case k.sup when 'brees' then 'Bree''s New World' else initcap(k.sup) end as leverancier,
  initcap(replace(split_part(e.key, '~', 2), '-', ' ')) as serie,
  case e.value->>'s' when 'wel' then 'Houden' when 'niet' then 'Niet houden' else e.value->>'s' end as keuze,
  case e.value->>'oc' when 'klant' then 'Online, voor klanten' when 'intern' then 'Online, alleen intern'
                      when 'niet' then 'Niet online' end as online,
  nullif(concat_ws(', ',
    case when e.value->'lab'->>0 = '1' then 'Hospitality' end,
    case when e.value->'lab'->>1 = '1' then 'Care' end,
    case when e.value->'lab'->>2 = '1' then 'Student housing' end,
    case when e.value->'lab'->>3 = '1' then 'Leisure' end,
    case when e.value->'lab'->>4 = '1' then 'Smart living' end), '') as labels,
  (select count(*) from jsonb_each(coalesce(e.value->'v','{}'::jsonb)) u where u.value::text = '1') as uitvoeringen_houden,
  (select count(*) from jsonb_each(coalesce(e.value->'v','{}'::jsonb)) u where u.value::text = '0') as uitvoeringen_niet,
  (e.value->>'t')::timestamptz                      as gekozen_op,
  k.bijgewerkt_door                                 as account,
  e.key                                             as serie_code
from public.keuzes k
cross join lateral jsonb_each(k.c) e
where e.value->>'s' is not null;

create or replace view public.keuzes_per_uitvoering
with (security_invoker = true) as
select
  k.naam                                            as beoordelaar,
  case k.sup when 'brees' then 'Bree''s New World' else initcap(k.sup) end as leverancier,
  initcap(replace(split_part(e.key, '~', 2), '-', ' ')) as serie,
  u.key                                             as nummer_leverancier,
  case when u.value::text = '1' then 'Houden' else 'Niet houden' end as keuze,
  a.product, a.afas_nr, a.blom_naam,
  (e.value->>'t')::timestamptz                      as gekozen_op
from public.keuzes k
cross join lateral jsonb_each(k.c) e
cross join lateral jsonb_each(coalesce(e.value->'v','{}'::jsonb)) u
left join lateral (
  select ar.product, ar.afas_nr, ar.blom_naam from public.artikelen ar
   where ar.nummer_leverancier = u.key
     and lower(ar.leverancier) like case k.sup when 'brees' then 'bree%' else k.sup || '%' end
   order by ar.afas_nr nulls last limit 1) a on true
where e.value->>'s' = 'wel';

grant select on public.keuzes_per_serie, public.keuzes_per_uitvoering to authenticated;
revoke all on public.keuzes_per_serie, public.keuzes_per_uitvoering from anon;
