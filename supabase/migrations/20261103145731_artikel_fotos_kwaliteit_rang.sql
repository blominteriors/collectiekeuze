ALTER TABLE public.artikel_fotos
  ADD COLUMN IF NOT EXISTS breedte_px integer,
  ADD COLUMN IF NOT EXISTS hoogte_px integer,
  ADD COLUMN IF NOT EXISTS kwaliteit_rang text
    CHECK (kwaliteit_rang IN ('<600', '600-999', '1000-1499', '1500+'));

CREATE OR REPLACE VIEW public.artikel_fotos_kwaliteit AS
SELECT versie, leverancier, herkomst, kwaliteit_rang, count(*) AS aantal
FROM public.artikel_fotos
WHERE img IS NOT NULL
GROUP BY versie, leverancier, herkomst, kwaliteit_rang
ORDER BY versie, leverancier, herkomst, kwaliteit_rang;