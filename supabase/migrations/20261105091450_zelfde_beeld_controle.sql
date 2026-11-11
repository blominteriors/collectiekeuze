ALTER TABLE collectie.artikel_fotos ADD COLUMN IF NOT EXISTS beeld_hash text;
CREATE OR REPLACE VIEW public.artikel_fotos WITH (security_invoker = true) AS SELECT * FROM collectie.artikel_fotos;

ALTER TABLE wachtrij.voorstel_fotos ADD COLUMN IF NOT EXISTS beeld_hash text, ADD COLUMN IF NOT EXISTS waarschuwing text;

DROP FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text, integer, jsonb, text);
CREATE FUNCTION public.voorstel_toevoegen(p_batch text, p_leverancier text, p_artikel_id text, p_zijde text, p_bron_url text, p_pagina text, p_storage_pad text, p_breedte integer, p_hoogte integer, p_rang text, p_door text, p_zekerheid integer DEFAULT NULL, p_waarom jsonb DEFAULT '[]'::jsonb, p_versie text DEFAULT 'test', p_hash text DEFAULT NULL, p_waarschuwing text DEFAULT NULL)
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO wachtrij.voorstel_fotos (batch, toegevoegd_door, leverancier, artikel_id, zijde, bron_url, pagina, storage_pad, breedte_px, hoogte_px, kwaliteit_rang, zekerheid, waarom, versie, beeld_hash, waarschuwing)
  VALUES (p_batch, p_door, p_leverancier, p_artikel_id, p_zijde, p_bron_url, p_pagina, p_storage_pad, p_breedte, p_hoogte, p_rang, p_zekerheid, coalesce(p_waarom, '[]'::jsonb), p_versie, p_hash, p_waarschuwing)
  RETURNING id;
$$;
REVOKE ALL ON FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text, integer, jsonb, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text, integer, jsonb, text, text, text) TO service_role;

-- Overzicht: eigen foto's (exact of web) met hetzelfde beeld bij artikelen die in het echt anders zijn.
-- Uitvoeringen zonder maten krijgen soort en maten van het artikel waarvan de code het langste begin is.
CREATE VIEW public.artikel_fotos_zelfde_beeld WITH (security_invoker = true) AS
WITH c AS (
  SELECT x.versie, x.leverancier, x.artikel_id,
         coalesce(x.soort, p.soort) AS soort, coalesce(x.breedte_cm, p.breedte_cm) AS breedte_cm, coalesce(x.diepte_cm, p.diepte_cm) AS diepte_cm,
         coalesce(x.zithoogte_cm, p.zithoogte_cm) AS zithoogte_cm, coalesce(x.hoogte_cm, p.hoogte_cm) AS hoogte_cm
  FROM collectie.collectie x
  LEFT JOIN LATERAL (
    SELECT y.* FROM collectie.collectie y
    WHERE y.versie = x.versie AND y.leverancier = x.leverancier AND y.artikel_id <> x.artikel_id
      AND starts_with(x.artikel_id, y.artikel_id)
      AND coalesce(y.breedte_cm, y.diepte_cm, y.zithoogte_cm, y.hoogte_cm) IS NOT NULL
    ORDER BY length(y.artikel_id) DESC LIMIT 1
  ) p ON coalesce(x.breedte_cm, x.diepte_cm, x.zithoogte_cm, x.hoogte_cm) IS NULL
)
SELECT a.versie, a.leverancier, a.artikel_id, a.zijde, b.artikel_id AS zelfde_beeld_als, b.zijde AS zijde_ander,
       ca.soort, cb.soort AS soort_ander,
       ca.zithoogte_cm, cb.zithoogte_cm AS zithoogte_ander, ca.hoogte_cm, cb.hoogte_cm AS hoogte_ander,
       ca.breedte_cm, cb.breedte_cm AS breedte_ander, ca.diepte_cm, cb.diepte_cm AS diepte_ander
FROM collectie.artikel_fotos a
JOIN collectie.artikel_fotos b
  ON b.versie = a.versie AND b.leverancier = a.leverancier AND b.artikel_id > a.artikel_id
 AND a.beeld_hash IS NOT NULL AND b.beeld_hash IS NOT NULL
 AND bit_count(('x' || a.beeld_hash)::bit(64) # ('x' || b.beeld_hash)::bit(64)) <= 4
JOIN c ca ON ca.versie = a.versie AND ca.leverancier = a.leverancier AND ca.artikel_id = a.artikel_id
JOIN c cb ON cb.versie = b.versie AND cb.leverancier = b.leverancier AND cb.artikel_id = b.artikel_id
WHERE a.herkomst IN ('exact', 'web') AND b.herkomst IN ('exact', 'web')
  AND (ca.soort IS DISTINCT FROM cb.soort
       OR abs(ca.zithoogte_cm - cb.zithoogte_cm) > 1 OR abs(ca.hoogte_cm - cb.hoogte_cm) > 1
       OR abs(ca.breedte_cm - cb.breedte_cm) > 1 OR abs(ca.diepte_cm - cb.diepte_cm) > 1);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.artikel_fotos_zelfde_beeld FROM anon, authenticated;