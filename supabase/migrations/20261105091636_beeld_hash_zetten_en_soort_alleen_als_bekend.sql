CREATE FUNCTION public.beeld_hash_zetten(p_versie text, p_leverancier text, p_hashes jsonb)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  WITH u AS (
    UPDATE collectie.artikel_fotos a SET beeld_hash = p_hashes ->> a.img::text
    WHERE a.versie = p_versie AND a.leverancier = p_leverancier AND a.img IS NOT NULL AND p_hashes ? a.img::text
    RETURNING 1)
  SELECT count(*)::integer FROM u;
$$;
REVOKE ALL ON FUNCTION public.beeld_hash_zetten(text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.beeld_hash_zetten(text, text, jsonb) TO service_role;

-- een onbekend soort telt niet als ander soort (zelfde regel als scripts/beeldcheck.py)
CREATE OR REPLACE VIEW public.artikel_fotos_zelfde_beeld WITH (security_invoker = true) AS
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
  AND ((ca.soort IS NOT NULL AND cb.soort IS NOT NULL AND ca.soort <> cb.soort)
       OR abs(ca.zithoogte_cm - cb.zithoogte_cm) > 1 OR abs(ca.hoogte_cm - cb.hoogte_cm) > 1
       OR abs(ca.breedte_cm - cb.breedte_cm) > 1 OR abs(ca.diepte_cm - cb.diepte_cm) > 1);