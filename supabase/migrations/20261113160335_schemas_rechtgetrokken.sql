-- Schema's rechtgetrokken (13 november 2026). Er wordt geen gegeven verwijderd.
-- Indeling daarna: public (wat de app en de acties aanroepen), collectie, app en namen (de echte tabellen),
-- controle (hulpweergaven), oud (vervangen of ongebruikt), backup (kopieën), wachtrij (afgeschaft, bewaard).
-- Toegepast op Database V1 op 13 november 2026.

-- 1. Het lege schema archief gaat op in oud. De drie tabellen waren leeg en worden nergens gebruikt.
alter table archief.artikel_fotos set schema oud;
alter table archief.collectie set schema oud;
alter table archief.prijzen set schema oud;
alter table oud.artikel_fotos rename to archief_artikel_fotos;
alter table oud.collectie rename to archief_collectie;
alter table oud.prijzen rename to archief_prijzen;
alter table oud.archief_artikel_fotos enable row level security;
alter table oud.archief_collectie enable row level security;
alter table oud.archief_prijzen enable row level security;
drop schema archief;

-- 2. Kopieën in backup: ook daar staat de beveiliging per rij aan (er zijn geen regels, dus alleen beheer kan erbij).
alter table backup.keuzes_korenstra_20261105 enable row level security;
alter table backup.keuzes_korenstra_20261105b enable row level security;
alter table backup.keuzes_live_20261105 enable row level security;

-- 3. Bij elk schema staat waar het voor is.
comment on schema public is 'Wat de app en de acties aanroepen: weergaven op de echte tabellen, functies en de tabel versies. Werklijst foto''s: artikel_fotos_breed.';
comment on schema collectie is 'De echte tabellen van de collectie: artikelen, collectie, prijzen, artikel_fotos, artikel_fotos_overig, foto_beoordelingen (logboek), zelfde_beeld_paren. Test en live staan in dezelfde tabellen (kolom versie).';
comment on schema app is 'De echte tabellen van de app: gebruikers en keuzes.';
comment on schema namen is 'De namenlijst van Blom (blom_namen, blom_namen_leveranciers), gebruikt bij de AFAS-import.';
comment on schema controle is 'Hulpweergaven bij het logboek van foto-beoordelingen, voor controle na een run.';
comment on schema oud is 'Vervangen of ongebruikt, bewaard: oude overzichten van foto''s en de lege archieftabellen (voorheen schema archief).';
comment on schema backup is 'Kopieën van voor een wijziging, met de datum in de naam. Niet bereikbaar voor de app.';
comment on schema wachtrij is 'Afgeschaft op 12 november 2026 (regels 3.1: geen wachtrij meer). Bewaard: 46 afgehandelde voorstellen. De functies voorstel_* in public horen hierbij.';
