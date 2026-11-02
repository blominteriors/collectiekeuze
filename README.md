# Blom Collectiekeuze

Swipe-app waarmee het Blom-team per leverancier beslist welke series in de collectie blijven of erbij komen.

## Opbouw

| Onderdeel | Waar | Inhoud |
|---|---|---|
| App (code) | Deze repository, gepubliceerd via GitHub Pages | `index.html`, `js/` |
| Inloggen | Supabase Auth | E-mailcode, alleen `@blominterieurs.nl` |
| Keuzes | Supabase tabel `keuzes` | Keuzes per beoordelaar en leverancier, live gedeeld |
| Modellen, foto's, prijzen, lettertypes | Supabase opslag, privé bucket `collectie` | Alleen leesbaar na inloggen |

Deze repository bevat bewust **geen** prijzen, artikeldata of lettertypebestanden: GitHub Pages is openbaar.
De `anon key` in `js/config.js` mag openbaar zijn; de beveiliging zit in de regels in `supabase/schema.sql`.

## Bestanden in de bucket `collectie`

```
suppliers.json                 lijst met leveranciers op de startpagina
<leverancier>.json             series en artikelen
<leverancier>-img-<n>.json     foto's (70 per bestand)
<leverancier>-sw.json          extra gegevens per leverancier
prijzen/<leverancier>.json     prijzen (alleen voor ingelogde Blom-gebruikers)
fonts/roc-medium.ttf, fonts/roc-light.ttf
```

## Nieuwe leverancier of nieuwe data

1. Upload de bestanden in het Supabase dashboard via Storage, bucket `collectie` (bestaand bestand overschrijven mag).
2. Voeg de leverancier toe aan `suppliers.json` en upload die opnieuw.
3. De app hoeft niet opnieuw gepubliceerd te worden.

## Code wijzigen

Elke wijziging op de branch `main` wordt automatisch door GitHub Pages gepubliceerd. De geschiedenis van de app staat in de commits.

## Eerste inrichting Supabase

1. SQL editor: `supabase/schema.sql` uitvoeren, daarna `supabase/keuzes-overzetten.sql`.
2. Storage: de inhoud van de map `collectie` uploaden naar bucket `collectie`.
3. Authentication, URL Configuration: Site URL en Redirect URL op het GitHub Pages adres zetten.
4. Authentication, Emails: in de template Magic Link `{{ .Token }}` opnemen, zodat de mail een code bevat.
5. Voor meer dan een paar inlogmails per uur: eigen SMTP instellen (Authentication, SMTP Settings).
6. `js/config.js`: project-URL en anon key invullen.
