-- Aanzicht van een foto: recht (recht vooraanzicht, zijaanzicht of achteraanzicht) of schuin (schuin aanzicht).
-- Een schuine voorzijde is een vervanger zolang er geen recht vooraanzicht is. Leeg = nog niet bepaald.
ALTER TABLE collectie.artikel_fotos ADD COLUMN IF NOT EXISTS aanzicht text CHECK (aanzicht IN ('recht', 'schuin'));
CREATE OR REPLACE VIEW public.artikel_fotos WITH (security_invoker = true) AS SELECT * FROM collectie.artikel_fotos;

ALTER TABLE wachtrij.voorstel_fotos ADD COLUMN IF NOT EXISTS aanzicht text CHECK (aanzicht IN ('recht', 'schuin'));

DROP FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text, integer, jsonb, text, text, text);
CREATE FUNCTION public.voorstel_toevoegen(p_batch text, p_leverancier text, p_artikel_id text, p_zijde text, p_bron_url text, p_pagina text, p_storage_pad text, p_breedte integer, p_hoogte integer, p_rang text, p_door text, p_zekerheid integer DEFAULT NULL, p_waarom jsonb DEFAULT '[]'::jsonb, p_versie text DEFAULT 'test', p_hash text DEFAULT NULL, p_waarschuwing text DEFAULT NULL, p_aanzicht text DEFAULT NULL)
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO wachtrij.voorstel_fotos (batch, toegevoegd_door, leverancier, artikel_id, zijde, bron_url, pagina, storage_pad, breedte_px, hoogte_px, kwaliteit_rang, zekerheid, waarom, versie, beeld_hash, waarschuwing, aanzicht)
  VALUES (p_batch, p_door, p_leverancier, p_artikel_id, p_zijde, p_bron_url, p_pagina, p_storage_pad, p_breedte, p_hoogte, p_rang, p_zekerheid, coalesce(p_waarom, '[]'::jsonb), p_versie, p_hash, p_waarschuwing, p_aanzicht)
  RETURNING id;
$$;
REVOKE ALL ON FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text, integer, jsonb, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text, integer, jsonb, text, text, text, text) TO service_role;

-- Overzicht per leverancier en versie: hoeveel voorzijden recht, schuin of nog onbekend zijn.
CREATE VIEW public.artikel_fotos_aanzicht WITH (security_invoker = true) AS
SELECT versie, leverancier, zijde, coalesce(aanzicht, 'onbekend') AS aanzicht, count(*) AS aantal
FROM collectie.artikel_fotos
WHERE img IS NOT NULL
GROUP BY versie, leverancier, zijde, coalesce(aanzicht, 'onbekend')
ORDER BY versie, leverancier, zijde, aanzicht;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON public.artikel_fotos_aanzicht FROM anon, authenticated;