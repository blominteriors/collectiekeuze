// Gebruiker helemaal verwijderen (alleen beheerders): van de gebruikerslijst én het inlogaccount.
//  1. haalt de persoon van de gebruikerslijst via de databasefunctie gebruiker_verwijder, met het inlogtoken van
//     de beheerder zelf. Die controleert of de aanvrager beheerder is en voorkomt dat je jezelf verwijdert.
//     Lukt dat niet, dan gebeurt er verder niets.
//  2. verwijdert het inlogaccount (Authentication → Users), zodat ook het wachtwoord niet meer werkt.
// Gemaakte keuzes blijven bewaard: app.keuzes.user_id verwijst met ON DELETE SET NULL naar het account,
// dus alleen de koppeling met het account wordt leeggemaakt.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

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

  let inv: { email?: string };
  try { inv = await req.json(); } catch { return antwoord(400, { error: "Ongeldige aanvraag." }); }
  const email = String(inv.email || "").trim().toLowerCase();
  if (!email.includes("@")) return antwoord(400, { error: "Geen geldig e-mailadres." });

  const url = Deno.env.get("SUPABASE_URL")!;
  const beheer = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const alsAanvrager = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: "Bearer " + token } },
  });

  const { data: wie, error: wieFout } = await beheer.auth.getUser(token);
  if (wieFout || !wie?.user?.email) return antwoord(401, { error: "Niet ingelogd." });

  // 1. van de gebruikerslijst (controleert ook of de aanvrager beheerder is)
  const { error: lijstFout } = await alsAanvrager.rpc("gebruiker_verwijder", { p_email: email });
  if (lijstFout) {
    const m = lijstFout.message || "";
    return antwoord(/not_granted|permission/i.test(m) ? 403 : 400,
      { error: /not_granted|permission/i.test(m) ? "Alleen een beheerder kan gebruikers verwijderen." : m });
  }

  // 2. het inlogaccount (bestaat het niet, bijvoorbeeld nooit ingelogd, dan is er niets te doen)
  let id: string | null;
  try { id = await zoekId(beheer, email); }
  catch { return antwoord(500, { error: "Van de lijst gehaald, maar het account kon niet worden opgezocht.", lijst: true }); }
  if (!id) return antwoord(200, { email, account: false });
  const { error } = await beheer.auth.admin.deleteUser(id);
  if (error) return antwoord(500, { error: "Van de lijst gehaald, maar het account verwijderen lukte niet: " + error.message, lijst: true });
  return antwoord(200, { email, account: true });
});

async function zoekId(beheer: ReturnType<typeof createClient>, email: string) {
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await beheer.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const u = data.users.find((x) => (x.email || "").toLowerCase() === email);
    if (u) return u.id;
    if (data.users.length < 1000) return null;
  }
  return null;
}
