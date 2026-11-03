// Verbindingsgegevens. Bij het publiceren schrijft de actie .github/workflows/publiceren.yml
// dit bestand per adres opnieuw, zodat het adres bepaalt welke database wordt gebruikt:
//   blominteriors.github.io/collectiekeuze/       -> Database V1, versie v1
//   blominteriors.github.io/collectiekeuze/test/  -> Database V1, versie test
// versie + bucket: welke versie (test, v1, v2 ...) en dus welke bucket en welke keuzes de app gebruikt.
// Zonder versie (bucket 'collectie') werkt de app met de oude platte opzet.
// De 'publishable key' mag openbaar zijn: alle data is afgeschermd met beveiligingsregels.
window.BLOM_CONFIG = {
  omgeving: 'live',
  url: 'https://vvvsvgtmslsjegbxppjf.supabase.co',
  anonKey: 'sb_publishable_NG__lC-SYFruk6q0KO3vsw_adHP5mLa',
  domein: '@blominterieurs.nl',
  versie: 'v1',
  bucket: 'v1'
};
