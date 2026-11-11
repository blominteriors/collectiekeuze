ALTER TABLE wachtrij.voorstel_fotos ADD COLUMN batch text NOT NULL DEFAULT 'handmatig';
CREATE INDEX voorstel_fotos_batch_idx ON wachtrij.voorstel_fotos (batch, status);

CREATE VIEW wachtrij.batches WITH (security_invoker = true) AS
SELECT batch,
       min(leverancier) AS leverancier,
       min(aangemaakt) AS aangemaakt,
       count(*) FILTER (WHERE status = 'voorstel') AS wachtend,
       count(*) FILTER (WHERE status = 'goedgekeurd') AS goedgekeurd,
       count(*) FILTER (WHERE status = 'afgewezen') AS afgewezen
FROM wachtrij.voorstel_fotos
GROUP BY batch
ORDER BY min(aangemaakt) DESC;

REVOKE ALL ON wachtrij.batches FROM anon, authenticated, public;
GRANT SELECT ON wachtrij.batches TO service_role;