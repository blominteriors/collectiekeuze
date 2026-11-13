-- Opruimen van schema public (13 november 2026): zes weergaven die de app en de acties niet gebruiken, verhuizen.
-- Er wordt niets verwijderd. Terugzetten: alter view <schema>.<naam> set schema public.
-- Toegepast op Database V1 op 13 november 2026.

create schema if not exists oud;
create schema if not exists controle;
comment on schema oud is 'Weergaven die vervangen zijn (zie public.artikel_fotos_breed). Bewaard, niet meer in gebruik.';
comment on schema controle is 'Hulpweergaven bij het logboek van foto-beoordelingen, voor controle na een run.';
grant usage on schema oud to service_role;
grant usage on schema controle to service_role;

alter view public.artikel_fotos_per_artikel set schema oud;
alter view public.artikel_fotos_overzicht set schema oud;
alter view public.artikel_fotos_aanzicht set schema oud;

alter view public.foto_beoordelingen_per_run set schema controle;
alter view public.foto_afwijsredenen set schema controle;
alter view public.foto_geplaatst_recent set schema controle;
