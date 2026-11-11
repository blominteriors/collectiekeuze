CREATE SCHEMA IF NOT EXISTS wachtrij;

CREATE TABLE wachtrij.voorstel_fotos (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  aangemaakt timestamptz NOT NULL DEFAULT now(),
  toegevoegd_door text NOT NULL,
  leverancier text NOT NULL,
  artikel_id text NOT NULL,
  zijde text NOT NULL CHECK (zijde IN ('voor', 'links', 'rechts', 'achter')),
  bron_url text NOT NULL,
  pagina text,
  storage_pad text,
  breedte_px integer,
  hoogte_px integer,
  kwaliteit_rang text CHECK (kwaliteit_rang IN ('<600', '600-999', '1000-1499', '1500+')),
  status text NOT NULL DEFAULT 'voorstel' CHECK (status IN ('voorstel', 'goedgekeurd', 'afgewezen')),
  beoordeeld_op timestamptz,
  opmerking text
);

ALTER TABLE wachtrij.voorstel_fotos ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON SCHEMA wachtrij FROM anon, authenticated, public;
REVOKE ALL ON ALL TABLES IN SCHEMA wachtrij FROM anon, authenticated, public;
GRANT USAGE ON SCHEMA wachtrij TO service_role;
GRANT SELECT, INSERT, UPDATE ON wachtrij.voorstel_fotos TO service_role;
GRANT USAGE, SELECT ON SEQUENCE wachtrij.voorstel_fotos_id_seq TO service_role;