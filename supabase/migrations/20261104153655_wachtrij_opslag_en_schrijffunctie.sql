INSERT INTO storage.buckets (id, name, public) VALUES ('voorstel', 'voorstel', false) ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.voorstel_toevoegen(p_batch text, p_leverancier text, p_artikel_id text, p_zijde text, p_bron_url text, p_pagina text, p_storage_pad text, p_breedte integer, p_hoogte integer, p_rang text, p_door text)
RETURNS bigint
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO wachtrij.voorstel_fotos (batch, toegevoegd_door, leverancier, artikel_id, zijde, bron_url, pagina, storage_pad, breedte_px, hoogte_px, kwaliteit_rang)
  VALUES (p_batch, p_door, p_leverancier, p_artikel_id, p_zijde, p_bron_url, p_pagina, p_storage_pad, p_breedte, p_hoogte, p_rang)
  RETURNING id;
$$;

REVOKE ALL ON FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.voorstel_toevoegen(text, text, text, text, text, text, text, integer, integer, text, text) TO service_role;