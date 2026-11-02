// Verbindingsgegevens. Bij het publiceren schrijft de actie .github/workflows/publiceren.yml
// dit bestand per adres opnieuw, zodat het adres bepaalt welke database wordt gebruikt:
//   blominteriors.github.io/collectiekeuze/       -> live project (Database V1)
//   blominteriors.github.io/collectiekeuze/test/  -> testproject (Test project)
// De 'publishable key' mag openbaar zijn: alle data is afgeschermd met beveiligingsregels.
window.BLOM_CONFIG = {
  omgeving: 'live',
  url: 'https://vvvsvgtmslsjegbxppjf.supabase.co',
  anonKey: 'sb_publishable_NG__lC-SYFruk6q0KO3vsw_adHP5mLa',
  domein: '@blominterieurs.nl',
  bucket: 'collectie'
};
