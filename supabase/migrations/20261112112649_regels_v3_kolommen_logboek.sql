-- Regels 3.0 voor foto's: kolommen in artikel_fotos en het logboek foto_beoordelingen.
-- Ontwerp: collectiekeuze-data/docs/fase-e/ontwerp-kolommen-logboek.md (goedgekeurd 12 november 2026).
-- Alleen toevoegen: geen kolom hernoemd of verwijderd. Test en live zitten in dezelfde tabellen; de app merkt hier niets van.
-- Let op: tot fase F leest de app de foto's uit de fotodelen in de buckets. foto_terugzetten zet alleen de database terug;
-- de fotodelen moeten tot die tijd door het script mee worden bijgewerkt.

-- 1. Kolommen in artikel_fotos. Leeg = nog niet beoordeeld met regels 3.
ALTER TABLE collectie.artikel_fotos
  ADD COLUMN IF NOT EXISTS niveau text CHECK (niveau IN ('app', 'beeldbank')),
  ADD COLUMN IF NOT EXISTS uitvoering_bevestigd text CHECK (uitvoering_bevestigd IN ('artikelnummer', 'maten')),
  ADD COLUMN IF NOT EXISTS bron_url text,
  ADD COLUMN IF NOT EXISTS pagina_url text,
  ADD COLUMN IF NOT EXISTS bron_soort text CHECK (bron_soort IN ('leverancier', 'dealer', 'overig', 'blom')),
  ADD COLUMN IF NOT EXISTS beschermd text CHECK (beschermd IN ('mens', 'blom')),
  ADD COLUMN IF NOT EXISTS regelversie text,
  ADD COLUMN IF NOT EXISTS beoordeling_id bigint;

COMMENT ON COLUMN collectie.artikel_fotos.niveau IS 'Regel E: app of beeldbank';
COMMENT ON COLUMN collectie.artikel_fotos.uitvoering_bevestigd IS 'Regel C1: bevestigd met artikelnummer of met maten';
COMMENT ON COLUMN collectie.artikel_fotos.bron_url IS 'Url van de foto zelf. bron blijft de omschrijving';
COMMENT ON COLUMN collectie.artikel_fotos.pagina_url IS 'Url van de pagina waar de foto op stond';
COMMENT ON COLUMN collectie.artikel_fotos.bron_soort IS 'leverancier, dealer, overig of blom';
COMMENT ON COLUMN collectie.artikel_fotos.beschermd IS 'Regels F7 en F8: gevuld = nooit automatisch vervangen (mens = goedgekeurd door een mens, blom = door Blom gemaakt)';
COMMENT ON COLUMN collectie.artikel_fotos.regelversie IS 'Regel H4: versie van de regels waarmee deze foto is beoordeeld';
COMMENT ON COLUMN collectie.artikel_fotos.beoordeling_id IS 'De regel in foto_beoordelingen die deze foto plaatste';

-- 2. Logboek. Elke beoordeling, ook niet plaatsen. Alleen toevoegen.
CREATE TABLE IF NOT EXISTS collectie.foto_beoordelingen (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run text NOT NULL,
  beoordeeld_op timestamptz NOT NULL DEFAULT now(),
  versie text NOT NULL REFERENCES public.versies(naam),
  leverancier text NOT NULL,
  artikel_id text NOT NULL,
  zijde text NOT NULL CHECK (zijde IN ('voor', 'links', 'rechts', 'achter')),
  uitkomst text NOT NULL CHECK (uitkomst IN ('geplaatst', 'niet_geplaatst', 'teruggezet')),
  niveau text CHECK (niveau IN ('app', 'beeldbank')),
  vervangreden text CHECK (vervangreden IN ('F1', 'F2', 'F3', 'F4', 'F5', 'F6')),
  afgewezen_op text[] NOT NULL DEFAULT '{}',
  oordeel jsonb NOT NULL DEFAULT '{}',
  scores jsonb NOT NULL DEFAULT '{}',
  uitvoering_bevestigd text CHECK (uitvoering_bevestigd IN ('artikelnummer', 'maten')),
  bron_url text,
  pagina_url text,
  bron_soort text CHECK (bron_soort IN ('leverancier', 'dealer', 'overig', 'blom')),
  bestand text,
  breedte_px integer,
  hoogte_px integer,
  aanzicht text CHECK (aanzicht IN ('recht', 'schuin')),
  beeld_hash text,
  vorige_beeld_hash text,
  vorige_foto jsonb,
  regelversie text NOT NULL,
  beoordelaar text,
  teruggezet_door text,
  terugzetting_van bigint REFERENCES collectie.foto_beoordelingen(id),
  -- Een geplaatste foto heeft een niveau; een niet geplaatste foto heeft minstens één afwijsregel.
  CHECK (uitkomst <> 'geplaatst' OR niveau IS NOT NULL),
  CHECK (uitkomst <> 'niet_geplaatst' OR cardinality(afgewezen_op) > 0),
  CHECK (uitkomst <> 'teruggezet' OR terugzetting_van IS NOT NULL)
);

COMMENT ON TABLE collectie.foto_beoordelingen IS 'Logboek van regels 3.0 (regel H1): elke beoordeling van een foto, ook niet plaatsen. Alleen toevoegen.';

CREATE INDEX IF NOT EXISTS foto_beoordelingen_plek_idx
  ON collectie.foto_beoordelingen (versie, leverancier, artikel_id, zijde, beoordeeld_op DESC);
CREATE INDEX IF NOT EXISTS foto_beoordelingen_run_idx ON collectie.foto_beoordelingen (run);

ALTER TABLE collectie.artikel_fotos
  ADD CONSTRAINT artikel_fotos_beoordeling_id_fkey
  FOREIGN KEY (beoordeling_id) REFERENCES collectie.foto_beoordelingen(id);

-- Alleen toevoegen: wijzigen en verwijderen worden geweigerd, ook met de beheersleutel.
CREATE OR REPLACE FUNCTION collectie.foto_beoordelingen_alleen_toevoegen()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  RAISE EXCEPTION 'foto_beoordelingen is een logboek: alleen toevoegen, niet wijzigen of verwijderen';
END $$;

CREATE TRIGGER foto_beoordelingen_niet_wijzigen
  BEFORE UPDATE OR DELETE ON collectie.foto_beoordelingen
  FOR EACH ROW EXECUTE FUNCTION collectie.foto_beoordelingen_alleen_toevoegen();

CREATE TRIGGER foto_beoordelingen_niet_legen
  BEFORE TRUNCATE ON collectie.foto_beoordelingen
  FOR EACH STATEMENT EXECUTE FUNCTION collectie.foto_beoordelingen_alleen_toevoegen();

-- Rechten: alleen de beheerder leest; schrijven alleen met de beheersleutel (scraper) of via foto_terugzetten.
ALTER TABLE collectie.foto_beoordelingen ENABLE ROW LEVEL SECURITY;
CREATE POLICY "foto_beoordelingen lezen voor beheerder" ON collectie.foto_beoordelingen
  FOR SELECT TO authenticated USING ((SELECT public.is_beheerder()));
REVOKE ALL ON collectie.foto_beoordelingen FROM anon, authenticated;
GRANT SELECT ON collectie.foto_beoordelingen TO authenticated;
GRANT SELECT, INSERT ON collectie.foto_beoordelingen TO service_role;

-- 3. Views in public, zodat de scripts er via de REST-api bij kunnen.
-- artikel_fotos: dezelfde kolommen als nu, de nieuwe achteraan. Rechten blijven staan.
CREATE OR REPLACE VIEW public.artikel_fotos WITH (security_invoker = true) AS
SELECT leverancier, artikel_id, zijde, herkomst, zekerheid, bron, bestand, img, getoond, bijgewerkt, versie, url,
       blom_naam, afas_nr, breedte_px, hoogte_px, kwaliteit_rang, beeld_hash, aanzicht,
       niveau, uitvoering_bevestigd, bron_url, pagina_url, bron_soort, beschermd, regelversie, beoordeling_id
FROM collectie.artikel_fotos;

CREATE OR REPLACE VIEW public.foto_beoordelingen WITH (security_invoker = true) AS
SELECT * FROM collectie.foto_beoordelingen;
REVOKE ALL ON public.foto_beoordelingen FROM anon, authenticated;
GRANT SELECT ON public.foto_beoordelingen TO authenticated;
GRANT SELECT, INSERT ON public.foto_beoordelingen TO service_role;

-- 4. Overzichten voor de controle na elke run (regel H3).
CREATE OR REPLACE VIEW public.foto_beoordelingen_per_run WITH (security_invoker = true) AS
SELECT run, versie, leverancier, min(beoordeeld_op) AS begin, max(beoordeeld_op) AS eind,
       count(*) AS beoordeeld,
       count(*) FILTER (WHERE uitkomst = 'geplaatst') AS geplaatst,
       count(*) FILTER (WHERE uitkomst = 'geplaatst' AND niveau = 'beeldbank') AS geplaatst_beeldbank,
       count(*) FILTER (WHERE uitkomst = 'geplaatst' AND niveau = 'app') AS geplaatst_app,
       count(*) FILTER (WHERE uitkomst = 'niet_geplaatst') AS niet_geplaatst,
       count(*) FILTER (WHERE uitkomst = 'teruggezet') AS teruggezet
FROM collectie.foto_beoordelingen
GROUP BY run, versie, leverancier;

CREATE OR REPLACE VIEW public.foto_afwijsredenen WITH (security_invoker = true) AS
SELECT b.run, b.versie, b.leverancier, r.regel, count(*) AS aantal
FROM collectie.foto_beoordelingen b, unnest(b.afgewezen_op) AS r(regel)
WHERE b.uitkomst = 'niet_geplaatst'
GROUP BY b.run, b.versie, b.leverancier, r.regel;

CREATE OR REPLACE VIEW public.foto_geplaatst_recent WITH (security_invoker = true) AS
SELECT b.id, b.run, b.beoordeeld_op, b.versie, b.leverancier, b.artikel_id, b.zijde, b.niveau, b.vervangreden,
       b.aanzicht, b.breedte_px, b.hoogte_px, b.uitvoering_bevestigd, b.bron_soort, b.bron_url, b.pagina_url,
       b.bestand AS nieuw_bestand, b.vorige_foto ->> 'url' AS vorige_url, b.scores,
       (f.beoordeling_id = b.id) AS nog_huidig
FROM collectie.foto_beoordelingen b
LEFT JOIN collectie.artikel_fotos f
  ON f.versie = b.versie AND f.leverancier = b.leverancier AND f.artikel_id = b.artikel_id AND f.zijde = b.zijde
WHERE b.uitkomst = 'geplaatst' AND b.beoordeeld_op > now() - interval '30 days';

REVOKE ALL ON public.foto_beoordelingen_per_run, public.foto_afwijsredenen, public.foto_geplaatst_recent FROM anon, authenticated;
GRANT SELECT ON public.foto_beoordelingen_per_run, public.foto_afwijsredenen, public.foto_geplaatst_recent TO authenticated, service_role;

-- 5. Terugzetten in één stap (regel H2). Alleen de beheerder of de beheersleutel.
-- Zet de foto van vóór beoordeling p_id terug. Was de plek toen leeg, dan wordt de regel weggehaald
-- (hij blijft in het logboek staan). Terugzetten is zelf ook weer terug te zetten.
CREATE OR REPLACE FUNCTION public.foto_terugzetten(p_id bigint, p_door text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  b collectie.foto_beoordelingen;
  huidig collectie.artikel_fotos;
  nieuw_id bigint;
BEGIN
  IF NOT (coalesce(auth.jwt() ->> 'role', '') = 'service_role' OR public.is_beheerder()) THEN
    RAISE EXCEPTION 'Alleen een beheerder mag een foto terugzetten';
  END IF;

  SELECT * INTO b FROM collectie.foto_beoordelingen WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Beoordeling % bestaat niet', p_id;
  END IF;
  IF b.uitkomst NOT IN ('geplaatst', 'teruggezet') THEN
    RAISE EXCEPTION 'Beoordeling % heeft niets geplaatst', p_id;
  END IF;

  SELECT * INTO huidig FROM collectie.artikel_fotos
  WHERE versie = b.versie AND leverancier = b.leverancier AND artikel_id = b.artikel_id AND zijde = b.zijde
  FOR UPDATE;
  IF NOT FOUND OR huidig.beoordeling_id IS DISTINCT FROM p_id THEN
    RAISE EXCEPTION 'De foto van beoordeling % is niet meer de huidige; zet eerst de latere terug', p_id;
  END IF;

  INSERT INTO collectie.foto_beoordelingen
    (run, versie, leverancier, artikel_id, zijde, uitkomst, niveau, bron_url, pagina_url, bron_soort, bestand,
     breedte_px, hoogte_px, aanzicht, beeld_hash, vorige_beeld_hash, vorige_foto, regelversie, beoordelaar,
     teruggezet_door, terugzetting_van)
  VALUES
    ('terugzetten', b.versie, b.leverancier, b.artikel_id, b.zijde, 'teruggezet',
     b.vorige_foto ->> 'niveau', b.vorige_foto ->> 'bron_url', b.vorige_foto ->> 'pagina_url',
     b.vorige_foto ->> 'bron_soort', b.vorige_foto ->> 'bestand',
     (b.vorige_foto ->> 'breedte_px')::integer, (b.vorige_foto ->> 'hoogte_px')::integer,
     b.vorige_foto ->> 'aanzicht', b.vorige_foto ->> 'beeld_hash', huidig.beeld_hash, to_jsonb(huidig),
     b.regelversie, NULL, coalesce(p_door, auth.jwt() ->> 'email'), p_id)
  RETURNING id INTO nieuw_id;

  DELETE FROM collectie.artikel_fotos
  WHERE versie = b.versie AND leverancier = b.leverancier AND artikel_id = b.artikel_id AND zijde = b.zijde;

  IF b.vorige_foto IS NOT NULL THEN
    INSERT INTO collectie.artikel_fotos
    SELECT * FROM jsonb_populate_record(NULL::collectie.artikel_fotos, b.vorige_foto);
    UPDATE collectie.artikel_fotos SET beoordeling_id = nieuw_id
    WHERE versie = b.versie AND leverancier = b.leverancier AND artikel_id = b.artikel_id AND zijde = b.zijde;
  END IF;

  RETURN nieuw_id;
END $$;

REVOKE ALL ON FUNCTION public.foto_terugzetten(bigint, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.foto_terugzetten(bigint, text) TO authenticated, service_role;
