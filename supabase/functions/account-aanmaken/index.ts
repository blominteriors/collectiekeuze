// Account aanmaken met een wachtwoord (alleen beheerders).
// Een beheerder vult in Menu → Gebruikers een e-mailadres, naam, rol en wachtwoord in. Deze functie:
//  1. zet de persoon op de gebruikerslijst via de databasefunctie gebruiker_zet, met het inlogtoken van de
//     beheerder zelf. Die functie controleert of de aanvrager beheerder is, of het adres op @blominterieurs.nl
//     eindigt en of de rol bestaat. Lukt dat niet, dan gebeurt er verder niets.
//  2. maakt het account aan met dat wachtwoord (e-mailadres meteen bevestigd, geen mail). Bestaat het account
//     al, dan wordt het wachtwoord overschreven.
// Het account krijgt de vlag wachtwoord_wijzigen: bij de eerste keer inloggen moet de persoon zelf een nieuw
// wachtwoord kiezen. Zo kent alleen hij het wachtwoord waarmee hij daarna inlogt.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const DOMEIN = "@blominterieurs.nl";
const ROLLEN = ["beheerder", "beoordelaar", "beoordelaar_zonder_prijzen"];
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const antwoord = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return antwoord(405, { error: "alleen POST" });

  const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  if (!token) return antwoord(401, { error: "Niet ingelogd." });

  let inv: { email?: string; naam?: string; rol?: string; wachtwoord?: string };
  try { inv = await req.json(); } catch { return antwoord(400, { error: "Ongeldige aanvraag." }); }
  const email = String(inv.email || "").trim().toLowerCase();
  const naam = String(inv.naam || "").trim();
  const rol = String(inv.rol || "");
  const wachtwoord = String(inv.wachtwoord || "");
  if (!/^[^@\s]+@blominterieurs\.nl$/.test(email)) return antwoord(400, { error: "Gebruik een " + DOMEIN + "-adres." });
  if (!ROLLEN.includes(rol)) return antwoord(400, { error: "Onbekende rol." });
  if (wachtwoord.length < 8) return antwoord(400, { error: "Het wachtwoord moet minimaal 8 tekens hebben." });

  const url = Deno.env.get("SUPABASE_URL")!;
  const beheer = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  // client met het token van de aanvrager: de databasefunctie ziet dan wie het vraagt
  const alsAanvrager = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: "Bearer " + token } },
  });

  const { data: wie, error: wieFout } = await beheer.auth.getUser(token);
  if (wieFout || !wie?.user?.email) return antwoord(401, { error: "Niet ingelogd." });

  // 1. op de gebruikerslijst (controleert ook of de aanvrager beheerder is)
  const { error: lijstFout } = await alsAanvrager.rpc("gebruiker_zet", { p_email: email, p_naam: naam, p_rol: rol });
  if (lijstFout) {
    const m = lijstFout.message || "";
    return antwoord(/not_granted|permission/i.test(m) ? 403 : 400,
      { error: /not_granted|permission/i.test(m) ? "Alleen een beheerder kan accounts aanmaken." : m });
  }

  // 2. account met wachtwoord, of het wachtwoord van een bestaand account overschrijven
  const meta = { wachtwoord: true, wachtwoord_wijzigen: true };
  const { error: maakFout } = await beheer.auth.admin.createUser({
    email, password: wachtwoord, email_confirm: true, user_metadata: meta,
  });
  if (!maakFout) return antwoord(200, { email, nieuw: true });

  const bestaat = (maakFout as { code?: string }).code === "email_exists" || /already been registered|already exists/i.test(maakFout.message);
  if (!bestaat) return antwoord(400, { error: wwFout(maakFout.message), lijst: true });

  const id = await zoekId(beheer, email);
  if (!id) return antwoord(500, { error: "Bestaand account niet gevonden.", lijst: true });
  const { error: zetFout } = await beheer.auth.admin.updateUserById(id, {
    password: wachtwoord, email_confirm: true, user_metadata: meta,
  });
  if (zetFout) return antwoord(400, { error: wwFout(zetFout.message), lijst: true });
  return antwoord(200, { email, nieuw: false });
});

// klein aantal accounts: doorzoek de lijst per 1000
async function zoekId(beheer: ReturnType<typeof createClient>, email: string) {
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await beheer.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) return null;
    const u = data.users.find((x) => (x.email || "").toLowerCase() === email);
    if (u) return u.id;
    if (data.users.length < 1000) return null;
  }
  return null;
}

function wwFout(m: string) {
  if (/weak|pwned|leaked|characters/i.test(m)) return "Dit wachtwoord is te zwak of komt voor in gelekte lijsten. Kies een ander.";
  return "Account aanmaken lukte niet: " + m;
}
