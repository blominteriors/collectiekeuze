# Blom Collectiekeuze

Swipe-app waarmee het Blom-team per leverancier beslist welke series in de collectie blijven of erbij komen.

## Adressen

| Adres | Tak | Supabase |
|---|---|---|
| https://blominterieurs.github.io/collectiekeuze/ | `main` (alleen final versies) | Database V1, versie `v1` (bucket `v1`) |
| https://blominterieurs.github.io/collectiekeuze/test/ | `ontwikkeling` (tussenversies) | Database V1, versie `test` (bucket `test`) |

Er is één Supabase project (Database V1). Elke versie heeft een eigen bucket met dezelfde mappen
(`collectie/`, `afbeeldingen/<leverancier>/`, `prijzen/<leverancier>/`, `algemeen/`). Keuzes, artikelen en foto's
hebben een kolom `versie`; de tabel `versies` houdt bij welke versie test, live of archief is. Accounts zijn gedeeld.

De actie `.github/workflows/publiceren.yml` publiceert beide bij elke push en schrijft per adres `js/config.js`.
Het adres bepaalt dus de versie, niet de app-code. Op het testadres krijgt de lokale opslag van de browser
het voorvoegsel `test:`, zodat test en live ook in de browser gescheiden blijven.

## Werkwijze

1. Wijzigingen gaan naar de tak `ontwikkeling` en zijn direct te zien op het testadres.
2. Databasewijzigingen komen als genummerd bestand in `supabase/migrations/`. Omdat er één project is, raakt een
   migratie ook live: maak wijzigingen altijd zo dat de huidige live site blijft werken (kolommen toevoegen, niet weghalen of hernoemen)
   en test ze via versie `test`.
3. Bij **final**: `ontwikkeling` samenvoegen in `main`. Een nieuwe live versie (v2) krijgt een eigen regel in `versies` en een eigen bucket;
   de vorige versie gaat op `archief`.

## Opbouw

| Onderdeel | Waar |
|---|---|
| App (code) | Deze repository, via GitHub Pages |
| Inloggen | Supabase Auth, e-mail, alleen `@blominterieurs.nl` |
| Keuzes | Supabase tabel `keuzes`, overzichten `keuzes_per_serie` en `keuzes_per_uitvoering` |
| Modellen, foto's, prijzen, lettertypes | Supabase opslag, privé bucket per versie (`test`, `v1`), gevuld vanuit `blominterieurs/collectiekeuze-data` |
| Artikellijst | Supabase tabel `artikelen`, gevuld vanuit `blominterieurs/collectiekeuze-data` |

Deze repository is openbaar en bevat bewust geen prijzen, artikeldata of lettertypebestanden.
