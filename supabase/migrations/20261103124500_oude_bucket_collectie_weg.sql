-- De oude platte bucket 'collectie' is opgeruimd (actie Bucket opruimen); de leesregel ervoor is niet meer nodig.
drop policy if exists "Blom leest collectie" on storage.objects;
