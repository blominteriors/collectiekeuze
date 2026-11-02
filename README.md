# Blom Collectiekeuze

Swipe-app waarmee het Blom-team per leverancier beslist welke series in de collectie blijven of erbij komen.

## Adressen

| Adres | Tak | Supabase project |
|---|---|---|
| https://blominteriors.github.io/collectiekeuze/ | `main` (alleen final versies) | Database V1 (live) |
| https://blominteriors.github.io/collectiekeuze/test/ | `ontwikkeling` (tussenversies) | Test project |

De actie `.github/workflows/publiceren.yml` publiceert beide bij elke push en schrijft per adres `js/config.js`.
Het adres bepaalt dus de database, niet de app-code. Op het testadres krijgt de lokale opslag van de browser
het voorvoegsel `test:`, zodat test en live ook in de browser gescheiden blijven.

## Werkwijze

1. Wijzigingen gaan naar de tak `ontwikkeling` en zijn direct te zien op het testadres.
2. Databasewijzigingen komen als genummerd bestand in `supabase/migrations/` en worden eerst alleen op het testproject uitgevoerd.
3. Bij **final**: nieuwe bestanden uit `supabase/migrations/` op Database V1 uitvoeren, daarna `ontwikkeling` samenvoegen in `main`.
   Zo past de live site altijd bij de live database.

## Opbouw

| Onderdeel | Waar |
|---|---|
| App (code) | Deze repository, via GitHub Pages |
| Inloggen | Supabase Auth, e-mail, alleen `@blominterieurs.nl` |
| Keuzes | Supabase tabel `keuzes`, overzichten `keuzes_per_serie` en `keuzes_per_uitvoering` |
| Modellen, foto's, prijzen, lettertypes | Supabase opslag, privé bucket `collectie`, gevuld vanuit `blominteriors/collectiekeuze-data` |
| Artikellijst | Supabase tabel `artikelen`, gevuld vanuit `blominteriors/collectiekeuze-data` |

Deze repository is openbaar en bevat bewust geen prijzen, artikeldata of lettertypebestanden.
