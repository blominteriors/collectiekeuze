CREATE SCHEMA IF NOT EXISTS collectie;
CREATE SCHEMA IF NOT EXISTS namen;
CREATE SCHEMA IF NOT EXISTS app;

ALTER TABLE public.collectie SET SCHEMA collectie;
ALTER TABLE public.artikelen SET SCHEMA collectie;
ALTER TABLE public.prijzen SET SCHEMA collectie;
ALTER TABLE public.artikel_fotos SET SCHEMA collectie;
ALTER TABLE public.blom_namen SET SCHEMA namen;
ALTER TABLE public.blom_namen_leveranciers SET SCHEMA namen;
ALTER TABLE public.keuzes SET SCHEMA app;

GRANT USAGE ON SCHEMA collectie, namen, app TO anon, authenticated, service_role;

CREATE VIEW public.collectie WITH (security_invoker = true) AS SELECT * FROM collectie.collectie;
CREATE VIEW public.artikelen WITH (security_invoker = true) AS SELECT * FROM collectie.artikelen;
CREATE VIEW public.prijzen WITH (security_invoker = true) AS SELECT * FROM collectie.prijzen;
CREATE VIEW public.artikel_fotos WITH (security_invoker = true) AS SELECT * FROM collectie.artikel_fotos;
CREATE VIEW public.blom_namen WITH (security_invoker = true) AS SELECT * FROM namen.blom_namen;
CREATE VIEW public.blom_namen_leveranciers WITH (security_invoker = true) AS SELECT * FROM namen.blom_namen_leveranciers;
CREATE VIEW public.keuzes WITH (security_invoker = true) AS SELECT * FROM app.keuzes;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.collectie, public.artikelen, public.prijzen, public.artikel_fotos, public.blom_namen, public.blom_namen_leveranciers, public.keuzes FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.keuze_zet(p_id text, p_sup text, p_naam text, p_c jsonb, p_vervang boolean DEFAULT false, p_versie text DEFAULT 'v1'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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