-- Basis: wie is een Blom-gebruiker, tabel keuzes met opslaanfunctie, live bijwerken, privé opslag.
create or replace function public.is_blom()
returns boolean
language sql stable
set search_path = ''
as $$
  select coalesce(lower(auth.jwt() ->> 'email') like '%@blominterieurs.nl', false)
$$;

create table if not exists public.keuzes (
  id               text primary key,
  sup              text not null,
  naam             text not null,
  c                jsonb not null default '{}'::jsonb,
  laatst           timestamptz not null default now(),
  user_id          uuid references auth.users(id) on delete set null,
  bijgewerkt_door  text
);
create index if not exists keuzes_sup_idx on public.keuzes (sup);
create index if not exists keuzes_user_idx on public.keuzes (user_id);

alter table public.keuzes enable row level security;

drop policy if exists "Blom leest keuzes" on public.keuzes;
create policy "Blom leest keuzes" on public.keuzes
  for select to authenticated using ((select public.is_blom()));

create or replace function public.keuze_zet(
  p_id text, p_sup text, p_naam text, p_c jsonb, p_vervang boolean default false)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  cur public.keuzes;
begin
  if not public.is_blom() then
    raise exception 'not_granted' using errcode = '42501';
  end if;
  select * into cur from public.keuzes where id = p_id for update;
  if not found then
    insert into public.keuzes (id, sup, naam, c, laatst, user_id, bijgewerkt_door)
    values (p_id, p_sup, p_naam, coalesce(p_c, '{}'::jsonb), now(), auth.uid(), auth.jwt() ->> 'email');
  else
    if cur.user_id is not null and cur.user_id <> auth.uid() then
      raise exception 'not_granted' using errcode = '42501';
    end if;
    update public.keuzes
       set naam = p_naam,
           sup  = p_sup,
           c    = case when p_vervang then coalesce(p_c, '{}'::jsonb) else c || coalesce(p_c, '{}'::jsonb) end,
           laatst = now(),
           user_id = coalesce(user_id, auth.uid()),
           bijgewerkt_door = auth.jwt() ->> 'email'
     where id = p_id;
  end if;
end;
$$;

revoke all on function public.keuze_zet(text, text, text, jsonb, boolean) from public, anon;
grant execute on function public.keuze_zet(text, text, text, jsonb, boolean) to authenticated;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'keuzes') then
    alter publication supabase_realtime add table public.keuzes;
  end if;
end $$;

insert into storage.buckets (id, name, public)
values ('collectie', 'collectie', false)
on conflict (id) do update set public = false;

drop policy if exists "Blom leest collectie" on storage.objects;
create policy "Blom leest collectie" on storage.objects
  for select to authenticated
  using (bucket_id = 'collectie' and (select public.is_blom()));
