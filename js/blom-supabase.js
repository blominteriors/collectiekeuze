/* Blom Collectiekeuze: koppeling met Supabase.
   Vervangt de Claude-functies die de app gebruikte:
   - claude.use('db')        -> tabel 'keuzes' (lezen, opslaan, live bijwerken) en prijzen uit de privé opslag
   - claude.use('downloads') -> gewone browserdownload
   - fetch('data/...')       -> dfetch('data/...') uit de privé opslag
   en zorgt voor inloggen met een e-mailcode, alleen voor @blominterieurs.nl. */
(function () {
  const CFG = window.BLOM_CONFIG;
  const DOMEIN = (CFG.domein || '@blominterieurs.nl').toLowerCase();
  const OMGEVING = CFG.omgeving || 'live';
  /* Versies: elke versie (test, v1, v2 ...) heeft een eigen bucket met mappen
     collectie/, afbeeldingen/<leverancier>/, prijzen/<leverancier>/ en algemeen/.
     De keuzes staan in één tabel met een kolom versie. Bucket 'collectie' is de oude platte opzet. */
  const VERSIE = CFG.versie || null;
  const OUD = !VERSIE || CFG.bucket === 'collectie';
  function bucketPad(pad) {
    if (OUD) return pad;
    const naam = pad.split('/').pop();
    if (pad.startsWith('fonts/')) return 'algemeen/' + pad;
    if (pad.startsWith('prijzen/')) {
      const stam = naam.replace(/\.json$/, ''), m = stam.match(/^(.*)-(\d+)$/);
      return 'prijzen/' + (m ? m[1] : stam) + '/' + naam;
    }
    if (naam.includes('-img-')) return 'afbeeldingen/' + naam.split('-img-')[0] + '/' + naam;
    return 'collectie/' + naam;
  }
  const metVersie = q => (OUD ? q : q.eq('versie', VERSIE));

  /* Test en live staan op hetzelfde webadres en delen dus de lokale opslag van de browser.
     Op de testomgeving krijgt elke sleutel een eigen voorvoegsel, zodat lokaal bewaarde
     keuzes van test nooit in de live versie terechtkomen (en andersom). */
  if (OMGEVING !== 'live') {
    try {
      const pre = OMGEVING + ':';
      const P = Storage.prototype, get = P.getItem, set = P.setItem, del = P.removeItem;
      const eigen = s => s === window.localStorage || s === window.sessionStorage;
      P.getItem = function (k) { return get.call(this, eigen(this) ? pre + k : k); };
      P.setItem = function (k, v) { return set.call(this, eigen(this) ? pre + k : k, v); };
      P.removeItem = function (k) { return del.call(this, eigen(this) ? pre + k : k); };
    } catch (e) { /* zonder lokale opslag werkt de app ook */ }
    document.addEventListener('DOMContentLoaded', () => {
      document.title = 'TEST · ' + document.title;
      // smalle strook bovenaan met een klein label: valt niet over knoppen of tekst, op telefoon en pc
      const tag = document.createElement('div');
      tag.textContent = 'Testomgeving';
      tag.title = 'Testomgeving · keuzes tellen niet mee voor live';
      tag.style.cssText = 'position:fixed;left:0;right:0;top:0;height:3px;z-index:150;background:#3A3A3A;pointer-events:none;' +
        'font:500 8.5px/1 Verdana,sans-serif;letter-spacing:.12em;text-transform:uppercase;color:transparent';
      const lbl = document.createElement('span');
      lbl.textContent = 'Test';
      lbl.style.cssText = 'position:absolute;top:3px;left:50%;transform:translateX(-50%);background:#3A3A3A;color:#FFFFFF;padding:2px 6px 3px;' +
        'font:500 8.5px/1 Verdana,sans-serif;letter-spacing:.12em;text-transform:uppercase';
      tag.appendChild(lbl);
      document.body.appendChild(tag);
    });
  }
  /* Komt deze pagina binnen via de inloglink uit de mail? En wacht deze browser zelf op die link
     (dan is hier op 'Stuur inloglink' geklikt)? Zo niet, dan is de link op een ander apparaat
     geopend dan waar is ingelogd, en tonen we meteen een code voor dat andere apparaat. */
  const VIA_LINK = /access_token=|type=magiclink/.test(location.hash + location.search);
  const WACHT = 'blom-wacht-op-link';
  let wachtHier = false;
  try { wachtHier = !!localStorage.getItem(WACHT); localStorage.removeItem(WACHT); } catch (e) {}
  const sb = window.supabase.createClient(CFG.url, CFG.anonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  window.sb = sb;
  const isBlom = u => !!(u && u.email && u.email.toLowerCase().endsWith(DOMEIN));

  /* ---------- bestanden uit de privé opslag ---------- */
  async function download(pad) {
    const { data, error } = await sb.storage.from(CFG.bucket).download(bucketPad(pad));
    if (error) throw norm(error);
    return data;
  }
  window.dfetch = async function (pad) {
    const blob = await download(String(pad).replace(/^data\//, ''));
    return new Response(blob, { headers: { 'content-type': 'application/json' } });
  };

  function norm(e) {
    const msg = (e && (e.message || e.error)) || 'onbekende fout';
    const err = new Error(msg);
    const st = e && (e.statusCode || e.status);
    if ((e && e.code === '42501') || /not_granted|permission|row-level|JWT/i.test(msg)) err.code = 'not_granted';
    else if (String(st) === '404' || String(st) === '400' || /not found/i.test(msg)) err.code = 'not_found';
    else err.code = (e && e.code) || 'unknown';
    return err;
  }
  const snap = (id, data) => ({ id, exists: !!data, data: () => (data ? data : undefined) });
  const rij = r => ({ naam: r.naam, sup: r.sup, c: r.c || {}, laatst: r.laatst });

  /* ---------- database: zelfde vorm als de Claude-database ---------- */
  const keuzes = {
    doc(id) {
      return {
        async get() {
          const { data, error } = await metVersie(sb.from('keuzes').select('naam,sup,c,laatst').eq('id', id)).maybeSingle();
          if (error) throw norm(error);
          return snap(id, data ? rij(data) : null);
        },
        async set(v) { return zet(id, v, true); },
        async update(v) { return zet(id, v, false); }
      };
    },
    where(veld, op, waarde) {
      return {
        onSnapshot(cb, onErr) {
          let gestopt = false, t = null;
          const laad = async () => {
            const { data, error } = await metVersie(sb.from('keuzes').select('id,naam,sup,c,laatst').eq(veld, waarde));
            if (gestopt) return;
            if (error) { if (onErr) onErr(norm(error)); return; }
            cb({ docs: data.map(r => snap(r.id, rij(r))) });
          };
          const kanaal = sb.channel('keuzes-' + waarde + '-' + Math.random().toString(36).slice(2))
            .on('postgres_changes', { event: '*', schema: 'public', table: 'keuzes', filter: veld + '=eq.' + waarde },
              () => { clearTimeout(t); t = setTimeout(laad, 250); })
            .subscribe();
          const poll = setInterval(() => { if (document.visibilityState === 'visible') laad(); }, 30000);
          laad();
          return () => { gestopt = true; clearTimeout(t); clearInterval(poll); sb.removeChannel(kanaal); };
        }
      };
    }
  };
  async function zet(id, v, vervang) {
    const args = { p_id: id, p_sup: v.sup, p_naam: v.naam, p_c: v.c || {}, p_vervang: vervang };
    if (!OUD) args.p_versie = VERSIE;
    const { error } = await sb.rpc('keuze_zet', args);
    if (error) throw norm(error);
  }
  const DB = {
    collection(naam) {
      if (naam !== 'keuzes') throw new Error('Onbekende collectie ' + naam);
      return keuzes;
    },
    doc(pad) {
      const [col, id] = String(pad).split('/');
      if (col !== 'prijzen') throw new Error('Onbekend document ' + pad);
      return {
        async get() {
          try {
            const blob = await download('prijzen/' + id + '.json');
            return snap(id, JSON.parse(await blob.text()));
          } catch (e) {
            if (e.code === 'not_found') return snap(id, null);
            throw e;
          }
        }
      };
    }
  };
  const DL = {
    async save({ filename, data }) {
      const url = URL.createObjectURL(data);
      const a = document.createElement('a');
      a.href = url; a.download = filename; document.body.appendChild(a); a.click(); a.remove();
      setTimeout(() => URL.revokeObjectURL(url), 10000);
    }
  };
  window.claude = { use: async k => (k === 'db' ? DB : k === 'downloads' ? DL : null) };

  /* ---------- lettertypes uit de privé opslag ---------- */
  async function laadFonts() {
    const fonts = [['fonts/roc-medium.ttf', '500'], ['fonts/roc-light.ttf', '200']];
    for (const [pad, gewicht] of fonts) {
      try {
        const buf = await (await download(pad)).arrayBuffer();
        const f = new FontFace('Roc Grotesk', buf, { weight: gewicht });
        await f.load(); document.fonts.add(f);
      } catch (e) { /* valt terug op Verdana */ }
    }
  }

  /* ---------- inloggen ---------- */
  const css = `
  .blogin{position:fixed;inset:0;z-index:200;background:#fff;display:flex;align-items:center;justify-content:center;padding:16px;font-family:var(--body,Verdana,sans-serif);color:var(--ink,#3A3A3A)}
  .blogin form{width:100%;max-width:380px;display:grid;gap:12px}
  .blogin h1{font-family:var(--display,Verdana,sans-serif);font-weight:500;font-size:30px;line-height:1.05;margin:0}
  .blogin p{margin:0;font-size:13px;line-height:1.45;color:var(--g400,#616161)}
  .blogin input{height:46px;border:1px solid var(--ink,#3A3A3A);border-radius:0;padding:0 12px;font:inherit;font-size:16px;color:inherit;background:#fff}
  .blogin button{height:46px;border:0;border-radius:0;background:var(--ink,#3A3A3A);color:#fff;font-family:var(--display,Verdana,sans-serif);font-weight:500;font-size:15px;cursor:pointer}
  .blogin button.link{background:none;color:var(--ink,#3A3A3A);height:auto;font-family:inherit;font-weight:400;font-size:12.5px;text-decoration:underline;justify-self:start;padding:0}
  .blogin button:disabled{opacity:.5;cursor:default}
  .blogin .fout{color:#B3261E}
  .blogin .eye{font-size:9.5px;letter-spacing:.14em;text-transform:uppercase;font-weight:500;color:var(--g400,#616161)}
  .buit{margin:8px 0 0;font-size:11.5px;color:var(--g400,#616161)}
  .buit button{border:0;background:none;padding:0;font:inherit;text-decoration:underline;color:var(--ink,#3A3A3A);cursor:pointer}`;
  let scherm = null, email = '', gestart = false;

  function maakScherm() {
    if (!scherm) {
      const st = document.createElement('style'); st.textContent = css; document.head.appendChild(st);
      scherm = document.createElement('div'); scherm.className = 'blogin';
      document.body.appendChild(scherm);
    }
    scherm.hidden = false;
  }
  function toonLogin(melding) {
    maakScherm();
    stapMail(melding);
  }
  function stapMail(melding) {
    scherm.innerHTML = `<form novalidate>
      <span class="eye">Blom Collectiekeuze</span>
      <h1>Inloggen</h1>
      <p>Vul je Blom e-mailadres in. Je krijgt een mail met een inloglink.</p>
      <input type="email" autocomplete="email" inputmode="email" placeholder="naam${DOMEIN}" required>
      <button type="submit">Stuur inloglink</button>
      <p class="fout" ${melding ? '' : 'hidden'}>${melding || ''}</p>
      <button type="button" class="link">Al ingelogd op je telefoon? Log in met een code van je telefoon</button></form>`;
    const f = scherm.querySelector('form'), inp = f.querySelector('input'), knop = f.querySelector('button'), fout = f.querySelector('.fout');
    inp.value = email; inp.focus();
    const adresOk = () => {
      email = inp.value.trim().toLowerCase();
      if (email.endsWith(DOMEIN)) return true;
      fout.textContent = 'Alleen adressen eindigend op ' + DOMEIN + ' hebben toegang.'; fout.hidden = false; return false;
    };
    // geen mail nodig: de code komt van een apparaat waarop je al bent ingelogd
    f.querySelector('.link').onclick = () => { if (adresOk()) stapCode(true); };
    f.onsubmit = async e => {
      e.preventDefault();
      if (!adresOk()) return;
      knop.disabled = true; knop.textContent = 'Versturen…';
      const terug = location.origin + location.pathname;
      const { error } = await sb.auth.signInWithOtp({ email, options: { shouldCreateUser: true, emailRedirectTo: terug } });
      if (error) { knop.disabled = false; knop.textContent = 'Stuur inloglink'; fout.textContent = /rate|limit/i.test(error.message) ? 'Er zijn te veel mails verstuurd. Probeer het over een paar minuten opnieuw.' : 'Versturen lukte niet: ' + error.message; fout.hidden = false; return; }
      try { localStorage.setItem(WACHT, String(Date.now())); } catch (e) {}
      stapCode();
    };
  }
  function stapCode(viaTelefoon) {
    const uitleg = viaTelefoon
      ? `<h1>Code van je telefoon</h1>
      <p>Open de app op je telefoon (of een ander apparaat waarop je al bent ingelogd als <b>${email}</b>). Kies in het menu <b>Inloggen op een ander apparaat</b> en typ hier de code die je daar ziet.</p>`
      : `<h1>Check je mail</h1>
      <p>We hebben een mail gestuurd naar <b>${email}</b>. De mail bevat een link, geen code.</p>
      <p><b>Mail op deze computer?</b> Klik op de link, dan ben je ingelogd.<br>
      <b>Mail op je telefoon?</b> Tik daar op de link. Je telefoon toont dan een code van 6 cijfers. Typ die code hieronder.</p>`;
    scherm.innerHTML = `<form novalidate>
      <span class="eye">Blom Collectiekeuze</span>
      ${uitleg}
      <input type="text" inputmode="numeric" autocomplete="one-time-code" placeholder="Inlogcode" maxlength="10" required>
      <button type="submit">Inloggen</button>
      <p class="fout" hidden></p>
      <button type="button" class="link">Ander e-mailadres of nieuwe code</button></form>`;
    const f = scherm.querySelector('form'), inp = f.querySelector('input'), knop = f.querySelector('button[type=submit]'), fout = f.querySelector('.fout');
    inp.focus();
    f.querySelector('.link').onclick = () => stapMail();
    f.onsubmit = async e => {
      e.preventDefault();
      const code = inp.value.replace(/\s/g, '');
      if (code.length < 6) return;
      knop.disabled = true; knop.textContent = 'Controleren…';
      let { error } = await sb.auth.verifyOtp({ email, token: code, type: 'email' });
      if (error) ({ error } = await sb.auth.verifyOtp({ email, token: code, type: 'magiclink' }));
      if (error) { knop.disabled = false; knop.textContent = 'Inloggen'; fout.textContent = 'Deze code klopt niet of is verlopen.'; fout.hidden = false; }
    };
  }

  /* ---------- inloggen op een ander apparaat ----------
     Wie hier al is ingelogd, vraagt een eenmalige inlogcode op (edge function apparaat-code)
     en typt die op het andere apparaat in. Er gaat geen mail uit. */
  async function toonApparaatCode(naLink) {
    maakScherm();
    const knopNieuw = '<button type="button" data-a="nieuw">Nieuwe code</button>';
    const knopTerug = `<button type="button" class="link" data-a="terug">${naLink === true ? 'Nee, verder naar de app op dit apparaat' : 'Terug naar de app'}</button>`;
    const kop = naLink === true ? 'Je bent ingelogd' : 'Inloggen op een ander apparaat';
    const zet = html => {
      scherm.innerHTML = `<form novalidate><span class="eye">Blom Collectiekeuze</span><h1>${kop}</h1>${html}</form>`;
      const n = scherm.querySelector('[data-a=nieuw]'), t = scherm.querySelector('[data-a=terug]');
      if (n) n.onclick = () => toonApparaatCode(naLink);
      if (t) t.onclick = () => { scherm.hidden = true; };
    };
    zet('<p>Code maken…</p>' + knopTerug);
    try {
      const { data, error } = await sb.functions.invoke('apparaat-code', { method: 'POST' });
      if (error || !data || !data.code) throw error || new Error('geen code');
      zet(`${naLink === true ? '<p>Wil je ook inloggen op je computer? Typ daar deze code in het inlogscherm:</p>' : `<p>Open de app op je computer, vul <b>${data.email}</b> in en kies <b>Log in met een code van je telefoon</b>. Typ daar deze code:</p>`}
        <p style="font-family:var(--display,Verdana,sans-serif);font-weight:500;font-size:38px;letter-spacing:.18em;color:var(--ink,#3A3A3A);margin:6px 0">${data.code}</p>
        <p>De code werkt één keer en is ongeveer een uur geldig. Deel hem met niemand.</p>${knopNieuw}${knopTerug}`);
    } catch (e) {
      zet('<p class="fout">Een code maken lukte niet. Probeer het zo nog eens.</p>' + knopNieuw + knopTerug);
    }
  }

  function uitlogRegel(user) {
    const form = document.getElementById('nameForm');
    if (form && !form.querySelector('.buit')) {
      const p = document.createElement('p'); p.className = 'buit';
      p.innerHTML = 'Ingelogd als ' + user.email + ' · <button type="button">Uitloggen</button> · <button type="button">Inloggen op een ander apparaat</button>';
      const [uit, ander] = p.querySelectorAll('button');
      uit.onclick = async () => { await sb.auth.signOut(); location.reload(); };
      ander.onclick = () => toonApparaatCode();
      form.appendChild(p);
    }
    const help = document.getElementById('mHelp');
    if (help && !document.getElementById('mApparaat')) {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'item'; b.id = 'mApparaat'; b.textContent = 'Inloggen op een ander apparaat';
      b.onclick = () => { const m = document.getElementById('menu'); if (m) m.hidden = true; toonApparaatCode(); };
      help.after(b);
    }
  }

  function ga(user) {
    if (gestart) return;
    gestart = true;
    if (scherm) scherm.hidden = true;
    window.BLOM_USER = user;
    uitlogRegel(user);
    laadFonts();
    if (typeof window.__blomBoot === 'function') window.__blomBoot();
    // link uit de mail geopend op een ander apparaat dan waar de link is aangevraagd: toon meteen
    // de code voor dat apparaat (buiten de inlog-callback van Supabase, anders blijft die hangen)
    if (VIA_LINK && !wachtHier) setTimeout(() => toonApparaatCode(true), 0);
  }

  async function start() {
    if (/JOUW-PROJECT|JOUW-ANON/.test(CFG.url + CFG.anonKey)) {
      toonLogin('Deze site is nog niet gekoppeld aan Supabase (js/config.js).'); return;
    }
    sb.auth.onAuthStateChange((ev, s) => {
      if (s && isBlom(s.user)) ga(s.user);
      else if (s && !isBlom(s.user)) { sb.auth.signOut(); toonLogin('Dit account heeft geen toegang. Gebruik je ' + DOMEIN + ' adres.'); }
    });
    const { data } = await sb.auth.getSession();
    const s = data && data.session;
    if (s && isBlom(s.user)) ga(s.user);
    else { if (s) await sb.auth.signOut(); toonLogin(); }
  }
  document.addEventListener('DOMContentLoaded', start);
})();
