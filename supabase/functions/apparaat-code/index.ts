// Inloggen op een ander apparaat zonder mail.
// Een collega die al is ingelogd (bijvoorbeeld op de telefoon, via de link in de mail) vraagt hier een
// inlogcode op voor zijn eigen e-mailadres. Die code typt hij op het andere apparaat (de pc) in het
// codeveld van het inlogscherm. Er wordt geen mail verstuurd: de code komt alleen terug naar de
// ingelogde collega zelf. Alleen adressen op @blominterieurs.nl krijgen een code.
import { createClient } from "npm:@supabase/supabase-js@2.118.0";

const DOMEIN = "@blominterieurs.nl";
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
  if (!token) return antwoord(401, { error: "niet ingelogd" });

  const beheer = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // wie vraagt de code aan? (controleert het inlogtoken bij Supabase zelf)
  const { data: wie, error: fout } = await beheer.auth.getUser(token);
  const email = wie?.user?.email?.toLowerCase();
  if (fout || !email) return antwoord(401, { error: "niet ingelogd" });
  if (!email.endsWith(DOMEIN)) return antwoord(403, { error: "geen toegang" });

  // maakt een nieuwe eenmalige inlogcode voor dit adres, zonder mail te versturen
  const { data, error } = await beheer.auth.admin.generateLink({ type: "magiclink", email });
  const code = data?.properties?.email_otp;
  if (error || !code) return antwoord(500, { error: "code maken lukte niet" });

  return antwoord(200, { email, code });
});
