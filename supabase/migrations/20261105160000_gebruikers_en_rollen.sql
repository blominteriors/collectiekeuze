-- Gebruikersbeheer: alleen vooraf toegevoegde gebruikers hebben toegang, met een rol.
--   beheerder   : ziet resultaten van iedereen, kan exporteren, mag keuzes onbeperkt aanpassen en beheert gebruikers
--   beoordelaar : ziet alleen de eigen keuzes; een leverancier doet hij/zij één keer. Na afronden zit die leverancier op slot.

create table if not exists app.gebruikers (
  email           text primary key check (email = lower(btrim(email)) and email like '%@blominterieurs.nl'),
  naam            text,
  rol             text not null check (rol in ('beheerder', 'beoordelaar')),
  toegevoegd_op   timestamptz not null default now(),
  toegevoegd_door text
);
alter table app.gebruikers enable row level security;   -- alleen via de functies hieronder

-- de eerste beheerders
insert into app.gebruikers (email, naam, rol, toegevoegd_door) values
  ('s.korenstra@blominterieurs.nl', 'S. Korenstra', 'beheerder', 'migratie'),
  ('r.nieuwhof@blominterieurs.nl',  'R. Nieuwhof',  'beheerder', 'migratie')
on conflict (email) do update set rol = excluded.rol;

-- rol van de ingelogde gebruiker (null = geen toegang)
create or replace function public.mijn_rol_tekst()
returns text language sql stable security definer set search_path = ''
as $$ select g.rol from app.gebruikers g where g.email = lower(auth.jwt() ->> 'email') $$;

create or replace function public.mijn_rol()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object('email', g.email, 'naam', g.naam, 'rol', g.rol)
  from app.gebruikers g where g.email = lower(auth.jwt() ->> 'email')
$$;

-- toegang: alleen wie in de gebruikerslijst staat (en een Blom-adres heeft)
create or replace function public.is_blom()
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(lower(auth.jwt() ->> 'email') like '%@blominterieurs.nl', false)
     and public.mijn_rol_tekst() is not null
$$;

create or replace function public.is_beheerder()
returns boolean language sql stable security definer set search_path = ''
as $$ select coalesce(public.mijn_rol_tekst() = 'beheerder', false) $$;

-- keuzes: beheerders lezen alles, beoordelaars alleen hun eigen keuzes
drop policy if exists "Blom leest keuzes" on app.keuzes;
create policy "Blom leest keuzes" on app.keuzes for select to authenticated
  using ((select public.is_beheerder()) or ((select public.is_blom()) and user_id = (select auth.uid())));

-- afgerond: na de laatste serie zet de app dit; daarna kan een beoordelaar deze leverancier niet meer wijzigen
alter table app.keuzes add column if not exists afgerond timestamptz;
create or replace view public.keuzes with (security_invoker = true) as
  select id, sup, naam, c, laatst, user_id, bijgewerkt_door, versie, afgerond from app.keuzes;

create or replace function public.keuze_zet(p_id text, p_sup text, p_naam text, p_c jsonb, p_vervang boolean default false, p_versie text default 'v1')
returns void language plpgsql security definer set search_path = 'public'
as $function$
declare
  cur app.keuzes;
begin
  if not public.is_blom() then
    raise exception 'not_granted' using errcode = '42501';
  end if;
  if not exists (select 1 from public.versies where naam = p_versie and status <> 'archief') then
    raise exception 'onbekende of gearchiveerde versie %', p_versie using errcode = '22023';
  end if;
  select * into cur from app.keuzes where versie = p_versie and id = p_id for update;
  if not found then
    insert into app.keuzes (versie, id, sup, naam, c, laatst, user_id, bijgewerkt_door)
    values (p_versie, p_id, p_sup, p_naam, coalesce(p_c, '{}'::jsonb), now(), auth.uid(), auth.jwt() ->> 'email');
  else
    if cur.user_id is not null and cur.user_id <> auth.uid() then
      raise exception 'not_granted' using errcode = '42501';
    end if;
    if cur.afgerond is not null and not public.is_beheerder() then
      raise exception 'afgerond' using errcode = '42501', hint = 'Deze leverancier is al afgerond.';
    end if;
    update app.keuzes
       set naam = p_naam,
           sup  = p_sup,
           c    = case when p_vervang then coalesce(p_c, '{}'::jsonb) else c || coalesce(p_c, '{}'::jsonb) end,
           laatst = now(),
           user_id = coalesce(user_id, auth.uid()),
           bijgewerkt_door = auth.jwt() ->> 'email'
     where versie = p_versie and id = p_id;
  end if;
end;
$function$;

create or replace function public.keuze_afronden(p_id text, p_versie text default 'v1')
returns void language sql security definer set search_path = ''
as $$
  update app.keuzes set afgerond = coalesce(afgerond, now())
  where versie = p_versie and id = p_id and user_id = auth.uid() and public.is_blom();
$$;

-- gebruikersbeheer (alleen beheerders)
create or replace function public.gebruikers_lijst()
returns table (email text, naam text, rol text, toegevoegd_op timestamptz, laatst_ingelogd timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_beheerder() then raise exception 'not_granted' using errcode = '42501'; end if;
  return query
    select g.email, g.naam, g.rol, g.toegevoegd_op, u.last_sign_in_at
    from app.gebruikers g left join auth.users u on lower(u.email) = g.email
    order by g.rol, g.email;
end $$;

create or replace function public.gebruiker_zet(p_email text, p_naam text, p_rol text)
returns void language plpgsql security definer set search_path = ''
as $$
declare e text := lower(btrim(p_email));
begin
  if not public.is_beheerder() then raise exception 'not_granted' using errcode = '42501'; end if;
  if e not like '%_@blominterieurs.nl' then raise exception 'Alleen @blominterieurs.nl-adressen' using errcode = '22023'; end if;
  if p_rol not in ('beheerder', 'beoordelaar') then raise exception 'Onbekende rol %', p_rol using errcode = '22023'; end if;
  if p_rol <> 'beheerder' and exists (select 1 from app.gebruikers where email = e and rol = 'beheerder')
     and (select count(*) from app.gebruikers where rol = 'beheerder') <= 1 then
    raise exception 'Er moet minstens één beheerder blijven' using errcode = '22023';
  end if;
  insert into app.gebruikers (email, naam, rol, toegevoegd_door)
  values (e, nullif(btrim(p_naam), ''), p_rol, auth.jwt() ->> 'email')
  on conflict (email) do update set naam = coalesce(nullif(btrim(p_naam), ''), app.gebruikers.naam), rol = excluded.rol;
end $$;

create or replace function public.gebruiker_verwijder(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare e text := lower(btrim(p_email));
begin
  if not public.is_beheerder() then raise exception 'not_granted' using errcode = '42501'; end if;
  if e = lower(auth.jwt() ->> 'email') then raise exception 'Je kunt jezelf niet verwijderen' using errcode = '22023'; end if;
  delete from app.gebruikers where email = e;
end $$;

-- een afgeronde leverancier weer openzetten voor een beoordelaar (alleen beheerders)
create or replace function public.keuze_heropenen(p_id text, p_versie text default 'v1')
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_beheerder() then raise exception 'not_granted' using errcode = '42501'; end if;
  update app.keuzes set afgerond = null where versie = p_versie and id = p_id;
end $$;

revoke all on function public.mijn_rol_tekst(), public.mijn_rol(), public.is_beheerder(), public.keuze_afronden(text, text),
  public.gebruikers_lijst(), public.gebruiker_zet(text, text, text), public.gebruiker_verwijder(text), public.keuze_heropenen(text, text)
  from public, anon;
grant execute on function public.mijn_rol_tekst(), public.mijn_rol(), public.is_beheerder(), public.keuze_afronden(text, text),
  public.gebruikers_lijst(), public.gebruiker_zet(text, text, text), public.gebruiker_verwijder(text), public.keuze_heropenen(text, text)
  to authenticated;
