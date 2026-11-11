ALTER TABLE wachtrij.voorstel_fotos ADD COLUMN zekerheid integer, ADD COLUMN waarom jsonb NOT NULL DEFAULT '[]'::jsonb, ADD COLUMN versie text NOT NULL DEFAULT 'test';

DROP FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text);

CREATE FUNCTION public.voorstel_toevoegen(p_batch text, p_leverancier text, p_artikel_id text, p_zijde text, p_bron_url text, p_pagina text, p_storage_pad text, p_breedte integer, p_hoogte integer, p_rang text, p_door text, p_zekerheid integer DEFAULT NULL, p_waarom jsonb DEFAULT '[]'::jsonb, p_versie text DEFAULT 'test')
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  INSERT INTO wachtrij.voorstel_fotos (batch, toegevoegd_door, leverancier, artikel_id, zijde, bron_url, pagina, storage_pad, breedte_px, hoogte_px, kwaliteit_rang, zekerheid, waarom, versie)
  VALUES (p_batch, p_door, p_leverancier, p_artikel_id, p_zijde, p_bron_url, p_pagina, p_storage_pad, p_breedte, p_hoogte, p_rang, p_zekerheid, coalesce(p_waarom, '[]'::jsonb), p_versie)
  RETURNING id;
$$;

CREATE FUNCTION public.voorstellen_van_batch(p_batch text)
RETURNS SETOF wachtrij.voorstel_fotos LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT * FROM wachtrij.voorstel_fotos WHERE batch = p_batch ORDER BY id;
$$;

CREATE FUNCTION public.voorstel_beoordelen(p_id bigint, p_status text, p_opmerking text DEFAULT NULL)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE wachtrij.voorstel_fotos SET status = p_status, beoordeeld_op = now(), opmerking = p_opmerking
  WHERE id = p_id AND status = 'voorstel';
$$;

REVOKE ALL ON FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text, integer, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.voorstellen_van_batch(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.voorstel_beoordelen(bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text, integer, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.voorstellen_van_batch(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.voorstel_beoordelen(bigint, text, text) TO service_role;