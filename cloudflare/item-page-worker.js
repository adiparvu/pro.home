// item-page — Cloudflare Worker serving the public "found item" page on
// https://xparvu.com/i/<uuid> (the URL inside every inventory QR label).
//
// v2 (user brief, 17:23 screenshot): Romanian-first with an RO/EN language
// selector (RO always listed first), "this item belongs to property X",
// the item's own pinned location with a tappable map card that opens
// Waze / Google Maps / Apple Maps, owner name + phone + email rows, the
// owner's chosen PRVIO app icon as the page badge (uploaded preview,
// migration 169), a neutral (untinted) item tile, and a footer that says
// just "Powered by PRVIO".
//
// v3 (IMG_8707-8709): the item glyph loses its boxed frame — the emoji
// stands alone, gently floating (motion pauses under
// prefers-reduced-motion) — and the card fades up on load. The badge and
// property line stay data-driven: the app now mirrors the CURRENT app
// icon to one stable URL per user (changing the icon repaints every
// page) and sends the real property entity's name.
//
// v4 (IMG_8704-8706): the "Open in PRVIO" CTA becomes black liquid
// glass — translucent black, backdrop blur, a slow specular sheen
// sweeping across (reduced-motion aware); items WITH coordinates show
// the REAL map (OpenStreetMap embed, keyless) with a pulsing ring on
// the pin — address-only items honestly keep the stylized grid; and
// "Powered by PRVIO" links the word PRVIO to the App Store listing.
//
// Reads ONLY the `public_items` projection (opt-in per item via the Lost &
// Found card); unknown / unpublished ids fall back to a friendly generic
// page instead of 404. The publishable key is public BY DESIGN (it ships
// inside the iOS app); only RLS guards the data. Env bindings
// SUPABASE_URL / SUPABASE_ANON_KEY override the defaults when set.
// Route: xparvu.com/i/*  — the rest of the zone is untouched.

const DEFAULT_SUPABASE_URL = "https://kwcanenheihuylaymwsl.supabase.co";
const DEFAULT_PUBLISHABLE_KEY = "sb_publishable_2gO8iM7dBqlbQqCiSTFeLQ_CV-DBgnC";

const UUID_RE = /^\/i\/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\/?$/i;

export default {
  async fetch(request, env) {
    const match = new URL(request.url).pathname.match(UUID_RE);
    const base = env?.SUPABASE_URL || DEFAULT_SUPABASE_URL;
    const key = env?.SUPABASE_ANON_KEY || DEFAULT_PUBLISHABLE_KEY;
    let item = null;
    if (match) {
      try {
        const r = await fetch(
          `${base}/rest/v1/public_items` +
            `?item_uuid=eq.${match[1]}` +
            `&select=item_name,owner_name,owner_phone,owner_email,owner_address,` +
            `property_name,latitude,longitude,app_icon_url,loaned_to,loaned_at`,
          {
            headers: {
              apikey: key,
              authorization: `Bearer ${key}`,
            },
          },
        );
        if (r.ok) item = (await r.json())[0] ?? null;
      } catch (_) {
        // Network hiccup → the generic page still helps the finder.
      }
    }
    return new Response(page(item, match ? match[1] : null), {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "no-store",
      },
    });
  },
};

const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]),
  );

function row(label, value, href) {
  if (!value) return "";
  const inner = href
    ? `<a href="${esc(href)}" style="font-size:14px;font-weight:500;color:#5ab4ff;text-decoration:none;word-break:break-word">${esc(value)}</a>`
    : `<span style="font-size:14px;font-weight:500;color:#f0f6ff;word-break:break-word">${esc(value)}</span>`;
  return `<div style="display:flex;gap:12px;padding:13px 16px;border-bottom:1px solid rgba(255,255,255,0.06)">
    <span data-i="${esc(label)}" style="min-width:72px;font-size:12px;color:rgba(255,255,255,0.4);flex-shrink:0"></span>${inner}</div>`;
}

function page(item, uuid) {
  const itemName = item?.item_name || "";
  const hasContact = !!(item?.owner_name || item?.owner_phone || item?.owner_email || item?.owner_address);
  const hasCoords = typeof item?.latitude === "number" && typeof item?.longitude === "number";
  const mapQuery = hasCoords
    ? `${item.latitude},${item.longitude}`
    : (item?.owner_address ? encodeURIComponent(item.owner_address) : null);
  const wazeHref = hasCoords
    ? `https://waze.com/ul?ll=${item.latitude},${item.longitude}&navigate=yes`
    : (mapQuery ? `https://waze.com/ul?q=${mapQuery}&navigate=yes` : null);
  const gmapsHref = mapQuery
    ? `https://www.google.com/maps/search/?api=1&query=${mapQuery}`
    : null;
  const amapsHref = hasCoords
    ? `https://maps.apple.com/?ll=${item.latitude},${item.longitude}&q=${encodeURIComponent(itemName || "PRVIO")}`
    : (mapQuery ? `https://maps.apple.com/?q=${mapQuery}` : null);

  const badge = item?.app_icon_url
    ? `<img src="${esc(item.app_icon_url)}" alt="" width="34" height="34" style="width:34px;height:34px;border-radius:9px;object-fit:cover;display:block">`
    : `<div style="width:34px;height:34px;border-radius:9px;background:#0D1420;display:flex;align-items:center;justify-content:center"><svg width="22" height="22" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" fill="white" d="M18 10 h28 v80 h-28 Z M46 10 L68 10 Q90 10 90 33 Q90 56 68 56 L46 56 Z M46 26 L65 26 Q74 26 74 33 Q74 40 65 40 L46 40 Z"/></svg></div>`;

  return `<!doctype html><html lang="ro"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(itemName || "PRVIO")} · PRVIO</title>
<style>
@keyframes prvFloat{0%,100%{transform:translateY(0) rotate(-2deg)}50%{transform:translateY(-8px) rotate(2deg)}}
@keyframes prvIn{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
@keyframes prvSheen{0%,55%{left:-60%}85%,100%{left:130%}}
@keyframes prvPulse{0%{transform:scale(.6);opacity:1}100%{transform:scale(2.6);opacity:0}}
.prvGlyph{display:inline-block;animation:prvFloat 4.5s ease-in-out infinite}
.prvCard{animation:prvIn .5s cubic-bezier(.2,.7,.3,1) both}
.prvCta{position:relative;overflow:hidden;transition:transform .15s ease}
.prvCta:active{transform:scale(.98)}
.prvCta::after{content:"";position:absolute;top:0;bottom:0;left:-60%;width:45%;background:linear-gradient(105deg,transparent,rgba(255,255,255,.16),transparent);transform:skewX(-20deg);animation:prvSheen 3.6s ease-in-out infinite}
.prvPin{position:absolute;left:50%;top:50%;width:14px;height:14px;margin:-7px 0 0 -7px;border-radius:50%;background:#ff4d4d;box-shadow:0 0 0 2px rgba(255,255,255,.85)}
.prvPin::before{content:"";position:absolute;inset:-4px;border-radius:50%;border:2px solid rgba(255,77,77,.6);animation:prvPulse 1.8s ease-out infinite}
@media (prefers-reduced-motion:reduce){.prvGlyph,.prvCard,.prvCta::after,.prvPin::before{animation:none}}
</style></head>
<body style="margin:0;min-height:100dvh;background:#0d1117;color:#f0f6ff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;display:flex;align-items:center;justify-content:center;padding:20px;box-sizing:border-box">
<div class="prvCard" style="background:rgba(255,255,255,0.07);border:1px solid rgba(255,255,255,0.12);border-radius:24px;padding:28px;max-width:420px;width:100%">

  <div style="display:flex;align-items:center;gap:10px;margin-bottom:22px">
    ${badge}
    <span style="font-size:11px;color:rgba(255,255,255,0.35);letter-spacing:1px;text-transform:uppercase">PRVIO</span>
    <span style="flex:1"></span>
    <span id="langs" style="display:flex;gap:4px;font-size:11px;font-weight:600;letter-spacing:.5px">
      <button data-lang="ro" style="all:unset;cursor:pointer;padding:5px 10px;border-radius:999px">RO</button>
      <button data-lang="en" style="all:unset;cursor:pointer;padding:5px 10px;border-radius:999px">EN</button>
    </span>
  </div>

  <div class="prvGlyph" style="font-size:56px;line-height:1;margin:2px 0 16px;filter:drop-shadow(0 12px 20px rgba(0,0,0,.5))">📦</div>
  <h1 style="font-size:26px;font-weight:700;margin:0 0 6px">${itemName ? esc(itemName) : '<span data-i="generic_title"></span>'}</h1>
  ${item?.property_name ? `<p style="font-size:13px;color:rgba(255,255,255,0.55);margin:0 0 18px"><span data-i="belongs"></span> <strong style="color:#f0f6ff">${esc(item.property_name)}</strong></p>` : '<div style="height:12px"></div>'}

  ${item ? `<div style="background:rgba(255,140,0,0.1);border:1px solid rgba(255,140,0,0.28);border-radius:14px;padding:16px 18px;margin:6px 0 18px">
    <h2 data-i="found_title" style="font-size:14px;font-weight:600;color:#ffaa44;margin:0 0 6px"></h2>
    <p style="font-size:13px;color:rgba(255,255,255,0.65);line-height:1.55;margin:0"><span data-i="found_body"></span>${item?.owner_name ? ` <strong style="color:rgba(255,255,255,.85)">${esc(item.owner_name)}</strong>` : ""}</p>
  </div>` : `<p data-i="standard_body" style="font-size:13px;color:rgba(255,255,255,0.55);line-height:1.6;margin:6px 0 18px"></p>`}

  ${uuid ? `<a class="prvCta" href="prvio://inventory/${esc(uuid)}" style="display:block;text-align:center;padding:15px;border-radius:14px;background:rgba(8,10,14,.72);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);border:1px solid rgba(255,255,255,.14);color:#f0f6ff;font-size:15px;font-weight:700;text-decoration:none;margin:0 0 14px;box-shadow:0 10px 30px rgba(0,0,0,.5),inset 0 1px 0 rgba(255,255,255,.12)"><span data-i="open_app"></span></a>` : ""}

  ${item?.loaned_to ? `<div style="background:rgba(120,110,255,0.1);border:1px solid rgba(120,110,255,0.3);border-radius:14px;padding:14px 18px;margin:0 0 14px">
    <h2 data-i="loan_title" style="font-size:13px;font-weight:600;color:#a9a0ff;margin:0 0 4px"></h2>
    <p style="font-size:13px;color:rgba(255,255,255,0.7);line-height:1.5;margin:0"><span data-i="loan_body"></span> <strong style="color:#f0f6ff">${esc(item.loaned_to)}</strong><span id="loanDate" data-date="${esc(item.loaned_at || "")}"></span></p>
  </div>` : ""}

  ${hasContact ? `<div style="background:rgba(255,255,255,0.04);border-radius:14px;overflow:hidden;margin-bottom:14px">
    ${row("l_owner", item?.owner_name)}
    ${row("l_phone", item?.owner_phone, item?.owner_phone ? `tel:${item.owner_phone}` : undefined)}
    ${row("l_email", item?.owner_email, item?.owner_email ? `mailto:${item.owner_email}` : undefined)}
    ${row("l_address", item?.owner_address)}
  </div>` : ""}

  ${(hasCoords || mapQuery) ? `
  <button id="mapBtn" style="all:unset;cursor:pointer;display:block;width:100%;box-sizing:border-box;border-radius:14px;overflow:hidden;border:1px solid rgba(255,255,255,0.1);margin-bottom:14px">
    ${hasCoords ? `<div style="position:relative;height:150px">
      <iframe src="https://www.openstreetmap.org/export/embed.html?bbox=${item.longitude - 0.004}%2C${item.latitude - 0.002}%2C${item.longitude + 0.004}%2C${item.latitude + 0.002}&amp;layer=mapnik" style="width:100%;height:100%;border:0;pointer-events:none;filter:saturate(.85) contrast(1.05) brightness(.92)" loading="lazy" title="map"></iframe>
      <div class="prvPin"></div>
      <span data-i="map_open" style="position:absolute;bottom:10px;right:12px;font-size:11px;font-weight:600;color:#5ab4ff;background:rgba(13,17,23,.8);padding:5px 10px;border-radius:999px"></span>
    </div>` : `<div style="position:relative;height:110px;background:
        linear-gradient(rgba(90,180,255,0.06) 1px, transparent 1px),
        linear-gradient(90deg, rgba(90,180,255,0.06) 1px, transparent 1px),
        linear-gradient(160deg, #10161f, #0b1a2a);
        background-size:22px 22px,22px 22px,cover;display:flex;align-items:center;justify-content:center">
      <div style="font-size:30px;filter:drop-shadow(0 6px 12px rgba(90,180,255,.4))">📍</div>
      <span data-i="map_open" style="position:absolute;bottom:10px;right:12px;font-size:11px;font-weight:600;color:#5ab4ff;background:rgba(13,17,23,.7);padding:5px 10px;border-radius:999px"></span>
    </div>`}
    ${item?.owner_address ? `<div style="padding:10px 14px;background:rgba(255,255,255,0.04);font-size:12.5px;color:rgba(255,255,255,0.6);text-align:left">${esc(item.owner_address)}</div>` : ""}
  </button>` : ""}

  <p style="font-size:11px;color:rgba(255,255,255,0.18);text-align:center;margin:22px 0 0">Powered by <a href="https://apps.apple.com/app/id6780068431" style="color:rgba(255,255,255,0.4);font-weight:600;text-decoration:none">PRVIO</a></p>
</div>

${(wazeHref || gmapsHref || amapsHref) ? `
<div id="mapSheet" style="position:fixed;inset:0;display:none;align-items:flex-end;justify-content:center;background:rgba(4,6,10,.55);backdrop-filter:blur(6px);-webkit-backdrop-filter:blur(6px);padding:16px;box-sizing:border-box;z-index:2">
  <div style="width:100%;max-width:420px;background:rgba(20,26,36,.97);border:1px solid rgba(255,255,255,.12);border-radius:20px;padding:14px;box-sizing:border-box">
    <p data-i="map_choose" style="font-size:12px;font-weight:600;letter-spacing:.8px;text-transform:uppercase;color:rgba(255,255,255,.4);margin:4px 8px 12px"></p>
    ${wazeHref ? `<a href="${esc(wazeHref)}" style="display:block;padding:14px;border-radius:12px;background:rgba(255,255,255,.05);color:#f0f6ff;font-size:15px;font-weight:600;text-decoration:none;margin-bottom:8px">Waze</a>` : ""}
    ${gmapsHref ? `<a href="${esc(gmapsHref)}" style="display:block;padding:14px;border-radius:12px;background:rgba(255,255,255,.05);color:#f0f6ff;font-size:15px;font-weight:600;text-decoration:none;margin-bottom:8px">Google Maps</a>` : ""}
    ${amapsHref ? `<a href="${esc(amapsHref)}" style="display:block;padding:14px;border-radius:12px;background:rgba(255,255,255,.05);color:#f0f6ff;font-size:15px;font-weight:600;text-decoration:none;margin-bottom:8px">Apple Maps</a>` : ""}
    <button id="mapClose" data-i="cancel" style="all:unset;cursor:pointer;display:block;width:100%;text-align:center;padding:13px;border-radius:12px;background:rgba(255,255,255,.08);color:rgba(255,255,255,.7);font-size:14px;font-weight:600;box-sizing:border-box"></button>
  </div>
</div>` : ""}

<script>
  var I18N = {
    ro: {
      generic_title: "Obiect PRVIO",
      belongs: "Acest obiect aparține proprietății",
      found_title: "Ai găsit sau ai împrumutat acest obiect?",
      found_body: "Te rugăm să îl returnezi proprietarului. Mulțumim pentru onestitate!",
      generic_body: "Acest obiect aparține unui utilizator PRVIO. Dacă l-ai găsit sau împrumutat, te rugăm să încerci să îl returnezi proprietarului.",
      l_owner: "Proprietar", l_phone: "Telefon", l_email: "Email", l_address: "Adresă",
      map_open: "Deschide în hărți", map_choose: "Deschide locația cu", cancel: "Anulează",
      loan_title: "Împrumutat", loan_body: "Acest obiect este împrumutat lui", loan_since: " din ",
      open_app: "Deschide în PRVIO",
      standard_body: "Acest obiect face parte din inventarul unei proprietăți PRVIO. Dacă faci parte din proprietate, deschide-l direct în aplicație."
    },
    en: {
      generic_title: "PRVIO Item",
      belongs: "This item belongs to the property",
      found_title: "Found or borrowed this item?",
      found_body: "Please return it to the owner. Thank you for your honesty!",
      generic_body: "This item belongs to a PRVIO user. If you found or borrowed it, please try to return it to its owner.",
      l_owner: "Owner", l_phone: "Phone", l_email: "Email", l_address: "Address",
      map_open: "Open in maps", map_choose: "Open location with", cancel: "Cancel",
      loan_title: "On loan", loan_body: "This item is on loan to", loan_since: " since ",
      open_app: "Open in PRVIO",
      standard_body: "This item is part of a PRVIO property's inventory. If you are a member of the property, open it directly in the app."
    }
  };
  function apply(lang) {
    var dict = I18N[lang] || I18N.ro;
    document.documentElement.lang = lang;
    var nodes = document.querySelectorAll("[data-i]");
    for (var i = 0; i < nodes.length; i++) {
      var k = nodes[i].getAttribute("data-i");
      if (dict[k]) nodes[i].textContent = dict[k];
    }
    var loanDate = document.getElementById("loanDate");
    if (loanDate && loanDate.getAttribute("data-date")) {
      var d = new Date(loanDate.getAttribute("data-date"));
      if (!isNaN(d)) {
        var fmt = new Intl.DateTimeFormat(lang === "ro" ? "ro-RO" : "en-GB",
                                          { day: "numeric", month: "long", year: "numeric" });
        loanDate.textContent = dict.loan_since + fmt.format(d);
      }
    }
    var chips = document.querySelectorAll("#langs button");
    for (var j = 0; j < chips.length; j++) {
      var active = chips[j].getAttribute("data-lang") === lang;
      chips[j].style.background = active ? "rgba(255,255,255,.12)" : "transparent";
      chips[j].style.color = active ? "#f0f6ff" : "rgba(255,255,255,.4)";
    }
    try { localStorage.setItem("prvio.lang", lang); } catch (_) {}
  }
  var saved = "ro";
  try { saved = localStorage.getItem("prvio.lang") || "ro"; } catch (_) {}
  apply(saved);
  var chips = document.querySelectorAll("#langs button");
  for (var i = 0; i < chips.length; i++) {
    chips[i].addEventListener("click", function () { apply(this.getAttribute("data-lang")); });
  }
  var mapBtn = document.getElementById("mapBtn");
  var sheet = document.getElementById("mapSheet");
  if (mapBtn && sheet) {
    mapBtn.addEventListener("click", function () { sheet.style.display = "flex"; });
    document.getElementById("mapClose").addEventListener("click", function () { sheet.style.display = "none"; });
    sheet.addEventListener("click", function (ev) { if (ev.target === sheet) sheet.style.display = "none"; });
  }
</script>
</body></html>`;
}
