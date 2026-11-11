CREATE SCHEMA IF NOT EXISTS archief;
REVOKE ALL ON SCHEMA archief FROM anon, authenticated, public;
GRANT USAGE ON SCHEMA archief TO service_role;

CREATE TABLE archief.collectie (LIKE collectie.collectie INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE archief.collectie ADD COLUMN gearchiveerd_op timestamptz NOT NULL DEFAULT now();
CREATE TABLE archief.prijzen (LIKE collectie.prijzen INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE archief.prijzen ADD COLUMN gearchiveerd_op timestamptz NOT NULL DEFAULT now();
CREATE TABLE archief.artikel_fotos (LIKE collectie.artikel_fotos INCLUDING DEFAULTS INCLUDING CONSTRAINTS);
ALTER TABLE archief.artikel_fotos ADD COLUMN gearchiveerd_op timestamptz NOT NULL DEFAULT now();

ALTER TABLE archief.collectie ENABLE ROW LEVEL SECURITY;
ALTER TABLE archief.prijzen ENABLE ROW LEVEL SECURITY;
ALTER TABLE archief.artikel_fotos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ALL TABLES IN SCHEMA archief FROM anon, authenticated, public;
GRANT SELECT, INSERT, DELETE ON ALL TABLES IN SCHEMA archief TO service_role;

INSERT INTO archief.collectie SELECT *, now() FROM collectie.collectie WHERE versie = 'v1' AND leverancier IN ('blues', 'infiniti', 'ezpeleta', 'pedrali');
DELETE FROM collectie.collectie WHERE versie = 'v1' AND leverancier IN ('blues', 'infiniti', 'ezpeleta', 'pedrali');
INSERT INTO archief.prijzen SELECT *, now() FROM collectie.prijzen WHERE versie = 'v1' AND leverancier IN ('blues', 'infiniti', 'ezpeleta', 'pedrali');
DELETE FROM collectie.prijzen WHERE versie = 'v1' AND leverancier IN ('blues', 'infiniti', 'ezpeleta', 'pedrali');
INSERT INTO archief.artikel_fotos SELECT *, now() FROM collectie.artikel_fotos WHERE versie = 'v1' AND leverancier IN ('blues', 'infiniti', 'ezpeleta', 'pedrali');
DELETE FROM collectie.artikel_fotos WHERE versie = 'v1' AND leverancier IN ('blues', 'infiniti', 'ezpeleta', 'pedrali');