/* Blom Collectiekeuze: koppeling met Supabase.
   Vervangt de Claude-functies die de app gebruikte:
   - claude.use('db')        -> tabel 'keuzes' (lezen, opslaan, live bijwerken) en prijzen uit de privé opslag
   - claude.use('downloads') -> gewone browserdownload
   - fetch('data/...')       -> dfetch('data/...') uit de privé opslag
   en zorgt voor inloggen met e-mailadres en wachtwoord (eerste keer via een inloglink), alleen voor @blominterieurs.nl. */
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
  const LIMIET = 'Er kan nu even geen inlogmail worden verstuurd (maximaal 2 per uur). Heb je al een wachtwoord? Log daarmee in. Anders: probeer het over een uur opnieuw.';
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

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
    stapInloggen(melding);
  }
  function adresOk(inp, fout) {
    email = inp.value.trim().toLowerCase();
    if (email.endsWith(DOMEIN)) return true;
    fout.textContent = 'Alleen adressen eindigend op ' + DOMEIN + ' hebben toegang.'; fout.hidden = false; inp.focus(); return false;
  }

  /* Stap 1: inloggen met e-mailadres en wachtwoord. Geen wachtwoord (of vergeten)? Dan een inloglink per mail. */
  function stapInloggen(melding) {
    scherm.innerHTML = `<form novalidate>
      <span class="eye">Blom Collectiekeuze</span>
      <h1>Inloggen</h1>
      <input type="email" name="email" autocomplete="username" inputmode="email" placeholder="naam${DOMEIN}" required>
      <input type="password" name="wachtwoord" autocomplete="current-password" placeholder="Wachtwoord" required>
      <button type="submit">Inloggen</button>
      <p class="fout" ${melding ? '' : 'hidden'}>${melding || ''}</p>
      <button type="button" class="link">Nog geen wachtwoord, of vergeten? Stuur een inloglink</button></form>`;
    const f = scherm.querySelector('form'), [inp, ww] = f.querySelectorAll('input'), knop = f.querySelector('button[type=submit]'), fout = f.querySelector('.fout');
    inp.value = email; (email ? ww : inp).focus();
    f.querySelector('.link').onclick = () => { email = inp.value.trim().toLowerCase(); stapLink(); };
    f.onsubmit = async e => {
      e.preventDefault();
      if (!adresOk(inp, fout)) return;
      if (!ww.value) { ww.focus(); return; }
      knop.disabled = true; knop.textContent = 'Inloggen…';
      const { error } = await sb.auth.signInWithPassword({ email, password: ww.value });
      if (error) {
        knop.disabled = false; knop.textContent = 'Inloggen';
        fout.textContent = /invalid login|credentials/i.test(error.message)
          ? 'E-mailadres of wachtwoord klopt niet. Nog geen wachtwoord? Gebruik de inloglink hieronder.'
          : 'Inloggen lukte niet: ' + error.message;
        fout.hidden = false;
      }
    };
  }

  /* Inloglink per mail: voor de eerste keer, of als het wachtwoord kwijt is. */
  function stapLink() {
    scherm.innerHTML = `<form novalidate>
      <span class="eye">Blom Collectiekeuze</span>
      <h1>Inloglink</h1>
      <p>Vul je Blom e-mailadres in. Je krijgt een mail met een inloglink. Na het inloggen kies je een wachtwoord, daarna heb je geen mail meer nodig.</p>
      <input type="email" autocomplete="email" inputmode="email" placeholder="naam${DOMEIN}" required>
      <button type="submit">Stuur inloglink</button>
      <p class="fout" hidden></p>
      <button type="button" class="link">Terug naar inloggen met wachtwoord</button></form>`;
    const f = scherm.querySelector('form'), inp = f.querySelector('input'), knop = f.querySelector('button[type=submit]'), fout = f.querySelector('.fout');
    inp.value = email; inp.focus();
    f.querySelector('.link').onclick = () => { email = inp.value.trim().toLowerCase(); stapInloggen(); };
    f.onsubmit = async e => {
      e.preventDefault();
      if (!adresOk(inp, fout)) return;
      knop.disabled = true; knop.textContent = 'Versturen…';
      const terug = location.origin + location.pathname;
      const { error } = await sb.auth.signInWithOtp({ email, options: { shouldCreateUser: true, emailRedirectTo: terug } });
      if (error) { knop.disabled = false; knop.textContent = 'Stuur inloglink'; fout.textContent = /rate|limit|security purposes/i.test(error.message) ? LIMIET : 'Versturen lukte niet: ' + error.message; fout.hidden = false; return; }
      stapMailVerstuurd();
    };
  }
  function stapMailVerstuurd() {
    scherm.innerHTML = `<form novalidate>
      <span class="eye">Blom Collectiekeuze</span>
      <h1>Check je mail</h1>
      <p>We hebben een mail gestuurd naar <b>${esc(email)}</b>. Klik op de link in die mail en kies daarna een wachtwoord.</p>
      <p>Open je de mail op je telefoon? Dan log je daar in en kies je daar je wachtwoord. Log hier daarna in met je e-mailadres en dat wachtwoord.</p>
      <button type="button">Inloggen met wachtwoord</button></form>`;
    scherm.querySelector('button').onclick = () => stapInloggen();
  }

  /* Wachtwoord kiezen of wijzigen (alleen als je bent ingelogd). Bij het opslaan zetten we een
     vlag in de gebruikersgegevens, zodat de app weet dat dit account een wachtwoord heeft. */
  function toonWachtwoord(eerste) {
    maakScherm();
    scherm.innerHTML = `<form novalidate>
      <span class="eye">Blom Collectiekeuze</span>
      <h1>${eerste ? 'Kies een wachtwoord' : 'Wachtwoord wijzigen'}</h1>
      <p>${eerste ? 'Daarmee log je voortaan op elk apparaat in met je e-mailadres en dit wachtwoord, zonder mail.' : 'Kies een nieuw wachtwoord.'} Minimaal 8 tekens.</p>
      <input type="email" autocomplete="username" value="${esc(window.BLOM_USER ? window.BLOM_USER.email : email)}" readonly hidden>
      <input type="password" autocomplete="new-password" placeholder="Nieuw wachtwoord" minlength="8" required>
      <input type="password" autocomplete="new-password" placeholder="Herhaal wachtwoord" minlength="8" required>
      <button type="submit">Wachtwoord opslaan</button>
      <p class="fout" hidden></p>
      <button type="button" class="link">${eerste ? 'Later' : 'Annuleren'}</button></form>`;
    const f = scherm.querySelector('form'), [, w1, w2] = f.querySelectorAll('input'), knop = f.querySelector('button[type=submit]'), fout = f.querySelector('.fout');
    const meld = t => { fout.textContent = t; fout.hidden = false; };
    w1.focus();
    f.querySelector('.link').onclick = () => { scherm.hidden = true; };
    f.onsubmit = async e => {
      e.preventDefault();
      if (w1.value.length < 8) return meld('Het wachtwoord moet minimaal 8 tekens hebben.');
      if (w1.value !== w2.value) return meld('De twee wachtwoorden zijn niet gelijk.');
      knop.disabled = true; knop.textContent = 'Opslaan…';
      const { data, error } = await sb.auth.updateUser({ password: w1.value, data: { wachtwoord: true } });
      if (error) {
        knop.disabled = false; knop.textContent = 'Wachtwoord opslaan';
        return meld(/reauth/i.test(error.message) ? 'Log eerst opnieuw in met een inloglink en kies dan je wachtwoord.'
          : /weak|pwned|leaked/i.test(error.message) ? 'Dit wachtwoord is te zwak of komt voor in gelekte lijsten. Kies een ander.'
          : /same|different from the old/i.test(error.message) ? 'Dit is je huidige wachtwoord. Kies een ander.'
          : 'Opslaan lukte niet: ' + error.message);
      }
      if (data && data.user) window.BLOM_USER = data.user;
      scherm.innerHTML = `<form novalidate><span class="eye">Blom Collectiekeuze</span><h1>Wachtwoord opgeslagen</h1>
        <p>Log voortaan op elk apparaat in met <b>${esc(window.BLOM_USER.email)}</b> en dit wachtwoord.</p>
        <button type="button">Verder naar de app</button></form>`;
      scherm.querySelector('button').onclick = () => { scherm.hidden = true; };
    };
  }

  function uitlogRegel(user) {
    const form = document.getElementById('nameForm');
    if (form && !form.querySelector('.buit')) {
      const p = document.createElement('p'); p.className = 'buit';
      p.innerHTML = 'Ingelogd als ' + esc(user.email) + ' · <button type="button">Uitloggen</button> · <button type="button">Wachtwoord wijzigen</button>';
      const [uit, ww] = p.querySelectorAll('button');
      uit.onclick = async () => { await sb.auth.signOut(); location.reload(); };
      ww.onclick = () => toonWachtwoord(false);
      form.appendChild(p);
    }
    const help = document.getElementById('mHelp');
    if (help && !document.getElementById('mWachtwoord')) {
      const b = document.createElement('button');
      b.type = 'button'; b.className = 'item'; b.id = 'mWachtwoord'; b.textContent = 'Wachtwoord wijzigen';
      b.onclick = () => { const m = document.getElementById('menu'); if (m) m.hidden = true; toonWachtwoord(false); };
      const uit = document.createElement('button');
      uit.type = 'button'; uit.className = 'item'; uit.id = 'mUitloggen'; uit.textContent = 'Uitloggen';
      uit.onclick = async () => { await sb.auth.signOut(); location.reload(); };
      help.after(b, uit);
    }
  }

  /* Rol ophalen: alleen wie in de gebruikerslijst staat, heeft toegang (beheerder, beoordelaar of beoordelaar zonder prijzen).
     Bestaat de functie nog niet (database nog niet bijgewerkt), dan werkt de app zoals voorheen. */
  async function haalRol() {
    const { data, error } = await sb.rpc('mijn_rol');
    if (error) {
      if (error.code === 'PGRST202' || /mijn_rol/.test(error.message || '')) return { rol: 'beheerder', naam: null, oud: true };
      throw error;
    }
    return data;
  }
  window.blomRpc = (fn, args) => sb.rpc(fn, args || {});
  /* Brandvertragend per artikelnummer, letterlijk uit Supabase:
     prijzen.uitvoering ('Brandvertragend' / 'Niet brandvertragend') en artikelen.omschrijving ('Brandvertragend uitgevoerd'). */
  async function alles(maak) {
    const rijen = [];
    for (let van = 0; ; van += 1000) {
      const { data, error } = await maak().range(van, van + 999);
      if (error) throw error;
      rijen.push(...data);
      if (data.length < 1000) break;
    }
    return rijen;
  }
  /* Model, uitvoering en de korte uitvoeringsnaam per artikelnummer (tabel artikelen, standaard korte uitvoeringsnaam in de data-repo).
     Geeft {artikelnummer: [rij, ...]}: een artikelnummer kan bij Bree meer rijen hebben (zelfde code, andere maat); de app kiest
     dan op AFAS-nummer of afwerking. kort = titel van de tegel, maatk = maten die de uitvoering onderscheiden, mk = model kenmerken,
     kc/kr = controleren en reden (alleen voor de beheerder). */
  window.blomModellen = async (supNaam) => {
    const V = VERSIE || 'v1', uit = {};
    const rijen = await alles(() => sb.from('artikelen')
      .select('nummer_leverancier,afas_nr,afwerking,model,uitvoering,uitvoering_kort,maat_kort,model_kenmerken,kort_controleren,kort_reden')
      .eq('versie', V).eq('leverancier', supNaam).not('model', 'is', null));
    rijen.forEach(r => { if (!r.model) return; (uit[r.nummer_leverancier] = uit[r.nummer_leverancier] || []).push({
      model: r.model, uit: r.uitvoering || '', afas: r.afas_nr || '', fin: r.afwerking || '', kort: r.uitvoering_kort || '',
      maatk: r.maat_kort || '', mk: r.model_kenmerken || '', kc: !!r.kort_controleren, kr: r.kort_reden || '' }); });
    return uit;
  };
  window.blomBrandvertragend = async (supId, supNaam) => {
    const V = VERSIE || 'v1', fr = {}, nfr = {}, oms = {};
    // de beoordelaar zonder prijzen mag de tabel prijzen niet lezen: die krijgt alleen artikelnummer en uitvoering via een functie
    const zonder = window.BLOM_ROL && window.BLOM_ROL.rol === 'beoordelaar_zonder_prijzen';
    const prijs = zonder
      ? await alles(() => sb.rpc('brandvertragend_regels', { p_versie: V, p_leverancier: supId })).catch(() => [])
      : await alles(() => sb.from('prijzen').select('nummer_leverancier,uitvoering').eq('versie', V).eq('leverancier', supId).ilike('uitvoering', '%brandvertr%'));
    prijs.forEach(r => { if (/niet\s+brandvertr/i.test(r.uitvoering)) nfr[r.nummer_leverancier] = 1; else fr[r.nummer_leverancier] = 1; });
    const art = await alles(() => sb.from('artikelen').select('nummer_leverancier,omschrijving').eq('versie', V).eq('leverancier', supNaam).ilike('omschrijving', '%brandvertr%'));
    art.forEach(r => { if (!/niet\s+brandvertr/i.test(r.omschrijving)) oms[r.nummer_leverancier] = 1; });
    return { fr, nfr, oms };
  };

  async function ga(user) {
    if (gestart) return;
    gestart = true;
    let rol = null;
    try { rol = await haalRol(); }
    catch (e) { gestart = false; toonLogin('Je toegang kon niet worden gecontroleerd. Herlaad de pagina.'); return; }
    if (!rol) {
      gestart = false;
      await sb.auth.signOut();
      toonLogin('Je hebt nog geen toegang tot de Collectiekeuze. Vraag een beheerder om je toe te voegen.');
      return;
    }
    window.BLOM_ROL = rol;
    if (scherm) scherm.hidden = true;
    window.BLOM_USER = user;
    uitlogRegel(user);
    laadFonts();
    if (typeof window.__blomBoot === 'function') window.__blomBoot();
    // nog geen wachtwoord gekozen: vraag erom (buiten de inlog-callback van Supabase, anders kan die blijven hangen)
    if (!(user.user_metadata && user.user_metadata.wachtwoord)) setTimeout(() => toonWachtwoord(true), 0);
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
