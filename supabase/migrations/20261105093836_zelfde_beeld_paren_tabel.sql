-- Paren eigen foto's met hetzelfde beeld, berekend door scripts/vingerafdrukken.py (kleur en vorm van het product).
CREATE TABLE collectie.zelfde_beeld_paren (
  versie text NOT NULL, leverancier text NOT NULL,
  artikel_id text NOT NULL, zijde text NOT NULL,
  ander_artikel text NOT NULL, ander_zijde text NOT NULL,
  PRIMARY KEY (versie, leverancier, artikel_id, zijde, ander_artikel, ander_zijde)
);
ALTER TABLE collectie.zelfde_beeld_paren ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON collectie.zelfde_beeld_paren FROM anon, authenticated, public;
GRANT SELECT, INSERT, DELETE ON collectie.zelfde_beeld_paren TO service_role;
CREATE POLICY "Blom leest zelfde_beeld_paren" ON collectie.zelfde_beeld_paren FOR SELECT TO authenticated USING ((SELECT public.is_blom()));
GRANT SELECT ON collectie.zelfde_beeld_paren TO authenticated;

CREATE FUNCTION public.zelfde_beeld_zetten(p_versie text, p_leverancier text, p_paren jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE n integer;
BEGIN
  DELETE FROM collectie.zelfde_beeld_paren WHERE versie = p_versie AND leverancier = p_leverancier;
  INSERT INTO collectie.zelfde_beeld_paren (versie, leverancier, artikel_id, zijde, ander_artikel, ander_zijde)
  SELECT p_versie, p_leverancier, x.artikel_id, x.zijde, x.ander_artikel, x.ander_zijde
  FROM jsonb_to_recordset(p_paren) AS x(artikel_id text, zijde text, ander_artikel text, ander_zijde text)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.zelfde_beeld_zetten(text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.zelfde_beeld_zetten(text, text, jsonb) TO service_role;

-- Overzicht: paren uit de tabel, alleen als de artikelen in het echt verschillen (soort of maten).
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
SELECT z.versie, z.leverancier, z.artikel_id, z.zijde, z.ander_artikel AS zelfde_beeld_als, z.ander_zijde AS zijde_ander,
       ca.soort, cb.soort AS soort_ander,
       ca.zithoogte_cm, cb.zithoogte_cm AS zithoogte_ander, ca.hoogte_cm, cb.hoogte_cm AS hoogte_ander,
       ca.breedte_cm, cb.breedte_cm AS breedte_ander, ca.diepte_cm, cb.diepte_cm AS diepte_ander
FROM collectie.zelfde_beeld_paren z
JOIN c ca ON ca.versie = z.versie AND ca.leverancier = z.leverancier AND ca.artikel_id = z.artikel_id
JOIN c cb ON cb.versie = z.versie AND cb.leverancier = z.leverancier AND cb.artikel_id = z.ander_artikel
WHERE z.artikel_id < z.ander_artikel
  AND ((ca.soort IS NOT NULL AND cb.soort IS NOT NULL AND ca.soort <> cb.soort)
       OR abs(ca.zithoogte_cm - cb.zithoogte_cm) > 1 OR abs(ca.hoogte_cm - cb.hoogte_cm) > 1
       OR abs(ca.breedte_cm - cb.breedte_cm) > 1 OR abs(ca.diepte_cm - cb.diepte_cm) > 1);