// coming-soon — Cloudflare Worker serving the holding page for xparvu.com.
//
// Route: xparvu.com/* (and www.xparvu.com/*) — the catch-all. The item QR
// pages keep their own worker on the MORE SPECIFIC route xparvu.com/i/*,
// which Cloudflare always prefers, so /i/<uuid> is untouched.
//
// Deliberately brandless (IMG_8661) and deliberately app-less: the domain
// sale has nothing to do with the app, so POST /contact delivers straight
// to adi@xparvu.com via the zone's own Email Routing (send_email binding
// INQUIRY_MAIL — envelope goes to the verified destination inbox that
// adi@ forwards to). Nothing is stored anywhere.

import { EmailMessage } from "cloudflare:email";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/contact") {
      return handleContact(request, env);
    }
    // Apple App Site Association — universal links for the item QR labels:
    // with the matching Associated Domains entitlement in the app, scanning
    // https://xparvu.com/i/<uuid> opens PRVIO straight on the item.
    if (url.pathname === "/.well-known/apple-app-site-association" ||
        url.pathname === "/apple-app-site-association") {
      return new Response(JSON.stringify({
        applinks: {
          apps: [],
          details: [{
            appIDs: ["SU92TVZT8W.com.prvio.app"],
            // /i/* = inventory item labels, /p/* = plant labels — both open
            // the app's scan-landing sheet when PRVIO is installed.
            components: [{ "/": "/i/*" }, { "/": "/p/*" }],
          }],
        },
      }), {
        headers: {
          "content-type": "application/json",
          "cache-control": "public, max-age=3600",
        },
      });
    }
    // Plant label page (migration 174): the owner opting into the QR card
    // mirrors the plant's public details into `public_plants` — ANY phone
    // that scans sees name, species, in-garden-since (with age), location
    // and the watering rhythm. Unmirrored ids fall back to the generic
    // "open in PRVIO" card.
    const plantMatch = url.pathname.match(/^\/p\/([0-9a-f-]{36})\/?$/i);
    if (plantMatch) {
      let plant = null;
      try {
        const r = await fetch(
          `${SUPABASE_URL}/rest/v1/public_plants` +
            `?plant_uuid=eq.${plantMatch[1]}` +
            `&select=name,species,emoji,location,property_name,planted_at,watering_interval_days`,
          { headers: { apikey: SUPABASE_KEY, authorization: `Bearer ${SUPABASE_KEY}` } },
        );
        if (r.ok) plant = (await r.json())[0] ?? null;
      } catch (_) {}
      return new Response(plantPage(plant), {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "no-store",
        },
      });
    }
    // The hard hat is also the site icon — served straight from the worker.
    if (url.pathname === "/favicon.svg" || url.pathname === "/favicon.ico") {
      return new Response(FAVICON, {
        headers: {
          "content-type": "image/svg+xml",
          "cache-control": "public, max-age=86400",
        },
      });
    }
    return new Response(PAGE, {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "public, max-age=300",
      },
    });
  },
};

async function handleContact(request, env) {
  const json = (ok, status = 200) =>
    new Response(JSON.stringify({ ok }), {
      status,
      headers: { "content-type": "application/json" },
    });
  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json(false, 400);
  }
  const email = String(body?.email ?? "").trim().slice(0, 320);
  const message = String(body?.message ?? "").trim().slice(0, 4000);
  const name = String(body?.name ?? "").trim().slice(0, 200);
  // Honeypot: real people never fill the invisible field — pretend success.
  if (body?.website) return json(true);
  if (!email.includes("@") || email.length < 3 || !message) return json(false, 400);

  // Header values must stay single-line ASCII-safe.
  const clean = (s) => s.replace(/[\r\n]+/g, " ");
  const raw =
    `From: xparvu.com <inquiry@xparvu.com>\r\n` +
    `To: adi@xparvu.com\r\n` +
    `Reply-To: ${clean(name ? `${name} <${email}>` : email)}\r\n` +
    `Subject: Domain inquiry - xparvu.com\r\n` +
    `Date: ${new Date().toUTCString()}\r\n` +
    `Content-Type: text/plain; charset=utf-8\r\n` +
    `\r\n` +
    `New inquiry from the xparvu.com sale page\r\n` +
    `------------------------------------------\r\n` +
    `Name:  ${clean(name || "-")}\r\n` +
    `Email: ${clean(email)}\r\n` +
    `\r\n${message}\r\n`;
  try {
    await env.INQUIRY_MAIL.send(
      new EmailMessage("inquiry@xparvu.com", env.INQUIRY_DEST || "adi@xparvu.com", raw),
    );
    return json(true);
  } catch (_) {
    return json(false, 502);
  }
}

const FAVICON = `<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
  <rect width="120" height="120" rx="26" fill="#07090f"/>
  <path d="M22 74 A38 38 0 0 1 98 74 Z" fill="#FFC53D"/>
  <rect x="53" y="30" width="14" height="32" rx="7" fill="#FFD666"/>
  <rect x="12" y="72" width="96" height="13" rx="6.5" fill="#F5A623"/>
  <path d="M22 74 A38 38 0 0 1 60 36 L60 74 Z" fill="rgba(255,255,255,.14)"/>
</svg>`;

// Supabase read access for the plant pages — the publishable key is
// public BY DESIGN (it ships inside the iOS app); RLS guards the data.
const SUPABASE_URL = "https://kwcanenheihuylaymwsl.supabase.co";
const SUPABASE_KEY = "sb_publishable_2gO8iM7dBqlbQqCiSTFeLQ_CV-DBgnC";

const escP = (s) =>
  String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

// The public plant card (IMG_8728): name, species, in-garden-since with
// a computed age, location, watering rhythm — the same dark PRVIO look
// as the lost-item pages. `plant` null → the generic data-free card.
function plantPage(plant) {
  if (!plant) return PLANT_PAGE;
  const emoji = plant.emoji || "🌱";
  const rows = [];
  if (plant.species) rows.push(["Specie", plant.species]);
  if (plant.planted_at) {
    const d = new Date(plant.planted_at);
    if (!isNaN(d)) {
      const months = Math.max(0, Math.floor((Date.now() - d.getTime()) / 2629800000));
      const age = months < 1 ? "sub o lună"
        : months < 12 ? `${months} ${months === 1 ? "lună" : "luni"}`
        : `${Math.floor(months / 12)} ${Math.floor(months / 12) === 1 ? "an" : "ani"}${months % 12 ? ` și ${months % 12} luni` : ""}`;
      rows.push(["În grădină din",
        `${d.toLocaleDateString("ro-RO", { month: "long", year: "numeric" })} (${age})`]);
    }
  }
  if (plant.location) rows.push(["Locație", plant.location]);
  if (plant.watering_interval_days) rows.push(["Udare", `la fiecare ${plant.watering_interval_days} zile`]);
  if (plant.property_name) rows.push(["Proprietate", plant.property_name]);
  const rowsHTML = rows.map(([k, v]) =>
    `<div style="display:flex;gap:12px;padding:12px 16px;border-bottom:1px solid rgba(255,255,255,.06)">
      <span style="min-width:110px;font-size:12px;color:rgba(255,255,255,.4);flex-shrink:0;text-align:left">${escP(k)}</span>
      <span style="font-size:14px;font-weight:500;color:#f0f6ff;text-align:left">${escP(v)}</span></div>`).join("");
  return `<!doctype html><html lang="ro"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escP(plant.name)} · PRVIO</title>
<style>
@keyframes prvFloat{0%,100%{transform:translateY(0) rotate(-2deg)}50%{transform:translateY(-8px) rotate(2deg)}}
@media (prefers-reduced-motion: reduce){.g{animation:none !important}}
</style></head>
<body style="margin:0;background:#05070C;color:#f0f6ff;font-family:-apple-system,system-ui,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px">
<div style="max-width:380px;width:100%;text-align:center">
  <div class="g" style="font-size:64px;display:inline-block;animation:prvFloat 4.5s ease-in-out infinite">${escP(emoji)}</div>
  <h1 style="font-size:24px;margin:12px 0 4px">${escP(plant.name)}</h1>
  <p style="font-size:13px;color:rgba(255,255,255,.45);margin:0 0 20px">Plantă din grădina PRVIO</p>
  <div style="background:rgba(255,255,255,.04);border:1px solid rgba(255,255,255,.08);border-radius:16px;overflow:hidden;margin-bottom:18px">${rowsHTML}</div>
  <a href="https://apps.apple.com/app/id6780068431"
     style="display:block;background:rgba(8,10,14,.72);border:1px solid rgba(255,255,255,.14);color:#fff;text-decoration:none;font-weight:600;font-size:15px;padding:14px 18px;border-radius:14px">
    Deschide în PRVIO</a>
</div>
</body></html>`;
}

// Data-free plant-label landing: shown when the plant was never mirrored.
const PLANT_PAGE = `<!doctype html><html lang="ro"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Plantă · PRVIO</title>
<style>
@keyframes prvFloat{0%,100%{transform:translateY(0) rotate(-2deg)}50%{transform:translateY(-8px) rotate(2deg)}}
@media (prefers-reduced-motion: reduce){.g{animation:none !important}}
</style></head>
<body style="margin:0;background:#05070C;color:#f0f6ff;font-family:-apple-system,system-ui,sans-serif;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px">
<div style="max-width:360px;text-align:center">
  <div class="g" style="font-size:64px;display:inline-block;animation:prvFloat 4.5s ease-in-out infinite">🌱</div>
  <h1 style="font-size:22px;margin:14px 0 8px">Etichetă de plantă PRVIO</h1>
  <p style="font-size:14px;color:rgba(255,255,255,.55);line-height:1.5;margin:0 0 22px">
    Detaliile plantei se deschid în aplicația PRVIO. Dacă e instalată,
    scanarea te duce direct la fișa ei.</p>
  <a href="https://apps.apple.com/app/id6780068431"
     style="display:block;background:rgba(8,10,14,.72);border:1px solid rgba(255,255,255,.14);color:#fff;text-decoration:none;font-weight:600;font-size:15px;padding:14px 18px;border-radius:14px">
    Descarcă PRVIO</a>
</div>
</body></html>`;

const PAGE = `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="Under construction.">
<link rel="icon" type="image/svg+xml" href="/favicon.svg">
<title>Under construction</title>
<style>
  :root { color-scheme: dark; }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #07090f; color: #f0f6ff; overflow: hidden;
    display: flex; align-items: center; justify-content: center;
  }

  /* Aurora backdrop — three blurred blobs drifting slowly. */
  .aurora { position: fixed; inset: -20%; filter: blur(90px); opacity: .45; z-index: 0; }
  .aurora span { position: absolute; border-radius: 50%; }
  .aurora span:nth-child(1) {
    width: 55vmax; height: 55vmax; left: -10%; top: -15%;
    background: radial-gradient(circle, #8a6d1c 0%, transparent 65%);
    animation: drift1 26s ease-in-out infinite alternate;
  }
  .aurora span:nth-child(2) {
    width: 45vmax; height: 45vmax; right: -12%; top: 20%;
    background: radial-gradient(circle, #1c3f8f 0%, transparent 65%);
    animation: drift2 32s ease-in-out infinite alternate;
  }
  .aurora span:nth-child(3) {
    width: 40vmax; height: 40vmax; left: 25%; bottom: -20%;
    background: radial-gradient(circle, #5b2a86 0%, transparent 65%);
    animation: drift3 38s ease-in-out infinite alternate;
  }
  @keyframes drift1 { to { transform: translate(12vmax, 8vmax) scale(1.15); } }
  @keyframes drift2 { to { transform: translate(-10vmax, -6vmax) scale(0.9); } }
  @keyframes drift3 { to { transform: translate(-8vmax, -10vmax) scale(1.2); } }

  /* Faint twinkling star field. */
  .stars, .stars::after {
    content: ""; position: fixed; inset: 0; z-index: 0;
    background-image:
      radial-gradient(1px 1px at 12% 22%, rgba(255,255,255,.7), transparent 40%),
      radial-gradient(1px 1px at 78% 12%, rgba(255,255,255,.55), transparent 40%),
      radial-gradient(1.5px 1.5px at 55% 68%, rgba(255,255,255,.5), transparent 40%),
      radial-gradient(1px 1px at 32% 84%, rgba(255,255,255,.6), transparent 40%),
      radial-gradient(1px 1px at 90% 55%, rgba(255,255,255,.45), transparent 40%),
      radial-gradient(1.5px 1.5px at 8% 60%, rgba(255,255,255,.4), transparent 40%);
    animation: twinkle 6s ease-in-out infinite alternate;
  }
  .stars::after { transform: translate(30px, 45px) scale(1.3); animation-delay: 3s; }
  @keyframes twinkle { from { opacity: .35; } to { opacity: .9; } }

  .card {
    position: relative; z-index: 1; text-align: center;
    padding: 52px 32px; max-width: 500px; width: calc(100% - 40px);
    background: rgba(255,255,255,.045);
    border: 1px solid rgba(255,255,255,.1);
    border-radius: 28px;
    backdrop-filter: blur(22px); -webkit-backdrop-filter: blur(22px);
    box-shadow: 0 30px 80px rgba(0,0,0,.45);
  }

  .hat { width: 120px; margin: 0 auto 26px; display: block;
         animation: bob 4.5s ease-in-out infinite;
         filter: drop-shadow(0 14px 30px rgba(255,197,61,.25)); }
  @keyframes bob { 0%,100% { transform: translateY(0) rotate(-2deg); }
                   50% { transform: translateY(-10px) rotate(2deg); } }

  h1 {
    font-size: 30px; font-weight: 800; letter-spacing: 5px; text-transform: uppercase;
    margin-bottom: 14px;
    background: linear-gradient(100deg, #f0f6ff 20%, #ffd666 45%, #f0f6ff 70%);
    background-size: 200% 100%;
    -webkit-background-clip: text; background-clip: text; color: transparent;
    animation: sheen 5.5s linear infinite;
  }
  @keyframes sheen { to { background-position: -200% 0; } }

  .bar { height: 4px; border-radius: 999px; overflow: hidden;
         background: rgba(255,255,255,.08); margin: 26px auto 34px; max-width: 280px; }
  .bar i { display: block; height: 100%; width: 40%; border-radius: 999px;
           background: linear-gradient(90deg, transparent, #ffd666, transparent);
           animation: slide 2.4s ease-in-out infinite; }
  @keyframes slide { from { transform: translateX(-110%); } to { transform: translateX(850%); } }

  .sale {
    font-size: 13px; line-height: 1.65; color: rgba(240,246,255,.45);
    border-top: 1px solid rgba(255,255,255,.08); padding-top: 22px;
  }
  .sale button {
    font: inherit; font-weight: 600; color: rgba(240,246,255,.85);
    background: none; border: none; cursor: pointer;
    border-bottom: 1px solid rgba(255,214,102,.5); padding-bottom: 1px;
    transition: color .2s, border-color .2s;
  }
  .sale button:hover { color: #ffd666; border-color: #ffd666; }

  /* Contact overlay */
  .overlay {
    position: fixed; inset: 0; z-index: 2; display: none;
    align-items: center; justify-content: center;
    background: rgba(4,6,10,.6);
    backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px);
  }
  .overlay.open { display: flex; }
  .sheet {
    width: calc(100% - 40px); max-width: 440px; text-align: left;
    background: rgba(18,22,32,.92);
    border: 1px solid rgba(255,255,255,.12); border-radius: 24px;
    padding: 28px; box-shadow: 0 40px 100px rgba(0,0,0,.6);
    animation: rise .3s cubic-bezier(.2,.9,.3,1.2);
  }
  @keyframes rise { from { opacity: 0; transform: translateY(24px) scale(.97); } }
  .sheet h2 { font-size: 18px; font-weight: 700; margin-bottom: 4px; }
  .sheet p.sub { font-size: 12.5px; color: rgba(240,246,255,.45); margin-bottom: 18px; }
  .sheet label { display: block; font-size: 11px; font-weight: 600; letter-spacing: .8px;
                 text-transform: uppercase; color: rgba(240,246,255,.4); margin: 12px 0 6px; }
  .sheet input, .sheet textarea {
    width: 100%; font: inherit; font-size: 14px; color: #f0f6ff;
    background: rgba(255,255,255,.06); border: 1px solid rgba(255,255,255,.12);
    border-radius: 12px; padding: 11px 13px; outline: none;
    transition: border-color .2s;
  }
  .sheet input:focus, .sheet textarea:focus { border-color: rgba(255,214,102,.55); }
  .sheet textarea { min-height: 110px; resize: vertical; }
  .hp { position: absolute; left: -9999px; opacity: 0; height: 0; overflow: hidden; }
  .actions { display: flex; gap: 10px; margin-top: 20px; }
  .actions button {
    flex: 1; font: inherit; font-size: 14px; font-weight: 600;
    padding: 12px; border-radius: 999px; cursor: pointer; border: none;
    transition: transform .15s, opacity .2s;
  }
  .actions button:active { transform: scale(.97); }
  .btn-cancel { background: rgba(255,255,255,.08); color: rgba(240,246,255,.7); }
  .btn-send { background: linear-gradient(120deg, #f5a623, #ffd666); color: #241a02; }
  .btn-send[disabled] { opacity: .55; cursor: default; }
  .note { font-size: 12px; margin-top: 12px; min-height: 16px; }
  .note.err { color: #ff9f8f; }
  .done { text-align: center; padding: 18px 0 6px; }
  .done .tick { width: 54px; height: 54px; margin: 0 auto 14px; border-radius: 50%;
                background: rgba(74,222,128,.12); border: 1px solid rgba(74,222,128,.4);
                display: flex; align-items: center; justify-content: center;
                font-size: 24px; color: #4ade80; animation: pop .35s cubic-bezier(.2,.9,.3,1.4); }
  @keyframes pop { from { transform: scale(.4); opacity: 0; } }
  .done h3 { font-size: 16px; margin-bottom: 4px; }
  .done p { font-size: 12.5px; color: rgba(240,246,255,.45); }

  @media (prefers-reduced-motion: reduce) {
    .aurora span, .stars, .stars::after, .hat, h1, .bar i, .sheet, .done .tick { animation: none; }
  }
</style></head>
<body>
<div class="aurora" aria-hidden="true"><span></span><span></span><span></span></div>
<div class="stars" aria-hidden="true"></div>
<main class="card">
  <svg class="hat" viewBox="0 0 120 78" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <path d="M18 58 A42 42 0 0 1 102 58 Z" fill="#FFC53D"/>
    <rect x="52" y="10" width="16" height="34" rx="8" fill="#FFD666"/>
    <rect x="6" y="56" width="108" height="14" rx="7" fill="#F5A623"/>
    <path d="M18 58 A42 42 0 0 1 60 16 L60 58 Z" fill="rgba(255,255,255,.14)"/>
  </svg>
  <h1>Under construction</h1>
  <div class="bar" aria-hidden="true"><i></i></div>
  <p class="sale">Interested in this domain? <button type="button" id="open">€500.000 — get in touch</button></p>
</main>

<div class="overlay" id="overlay" role="dialog" aria-modal="true" aria-labelledby="ct">
  <div class="sheet">
    <div id="formBox">
      <h2 id="ct">Domain inquiry</h2>
      <p class="sub">xparvu.com · asking €500.000</p>
      <form id="f">
        <label for="n">Name</label>
        <input id="n" name="name" autocomplete="name" maxlength="200">
        <label for="e">Email</label>
        <input id="e" name="email" type="email" required autocomplete="email" maxlength="320">
        <label for="m">Message</label>
        <textarea id="m" name="message" required maxlength="4000" placeholder="Your offer…"></textarea>
        <div class="hp" aria-hidden="true"><input name="website" tabindex="-1" autocomplete="off"></div>
        <div class="actions">
          <button type="button" class="btn-cancel" id="close">Cancel</button>
          <button type="submit" class="btn-send" id="send">Send</button>
        </div>
        <p class="note" id="note"></p>
      </form>
    </div>
    <div class="done" id="doneBox" hidden>
      <div class="tick">✓</div>
      <h3>Message sent</h3>
      <p>Thank you — you'll hear back if the offer is serious.</p>
      <div class="actions"><button type="button" class="btn-cancel" id="close2">Close</button></div>
    </div>
  </div>
</div>

<script>
  var overlay = document.getElementById('overlay');
  var note = document.getElementById('note');
  function open() { overlay.classList.add('open'); document.getElementById('e').focus(); }
  function shut() {
    overlay.classList.remove('open');
    document.getElementById('formBox').hidden = false;
    document.getElementById('doneBox').hidden = true;
    note.textContent = ''; note.classList.remove('err');
  }
  document.getElementById('open').addEventListener('click', open);
  document.getElementById('close').addEventListener('click', shut);
  document.getElementById('close2').addEventListener('click', shut);
  overlay.addEventListener('click', function (ev) { if (ev.target === overlay) shut(); });
  document.addEventListener('keydown', function (ev) { if (ev.key === 'Escape') shut(); });

  document.getElementById('f').addEventListener('submit', function (ev) {
    ev.preventDefault();
    var f = ev.target, send = document.getElementById('send');
    send.disabled = true; note.textContent = ''; note.classList.remove('err');
    fetch('/contact', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        name: f.name.value, email: f.email.value,
        message: f.message.value, website: f.website.value
      })
    }).then(function (r) { return r.json(); }).then(function (d) {
      send.disabled = false;
      if (d && d.ok) {
        document.getElementById('formBox').hidden = true;
        document.getElementById('doneBox').hidden = false;
        f.reset();
      } else {
        note.textContent = 'Something went wrong — please try again.';
        note.classList.add('err');
      }
    }).catch(function () {
      send.disabled = false;
      note.textContent = 'Network error — please try again.';
      note.classList.add('err');
    });
  });
</script>
</body></html>`;
