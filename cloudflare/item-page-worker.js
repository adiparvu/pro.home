// item-page — Cloudflare Worker serving the public "found item" page on
// https://xparvu.com/i/<uuid> (the URL inside every inventory QR label).
//
// Stopgap for the Next.js page at apps/web/src/app/i/[id]/page.tsx: the
// xparvu.com zone currently answers 404 for every path because the web app
// isn't deployed behind it, which turns every printed QR into "Not Found".
// This worker mirrors that page's exact semantics — it reads ONLY the
// `public_items` projection (publicly readable by policy; the owner opts in
// per item via "Show on public QR page"), and unknown / unpublished ids fall
// back to a friendly generic page instead of 404, because a finder should
// still learn the item is registered.
//
// The publishable key is public BY DESIGN (it ships inside the iOS app);
// only RLS policies guard the data. Env bindings SUPABASE_URL /
// SUPABASE_ANON_KEY override the defaults when set — nothing to configure
// for a plain paste-and-deploy.
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
            `&select=item_name,owner_name,owner_phone,owner_address,property_name`,
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
    return new Response(page(item), {
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
    <span style="min-width:64px;font-size:12px;color:rgba(255,255,255,0.4);flex-shrink:0">${esc(label)}</span>${inner}</div>`;
}

function page(item) {
  const itemName = item?.item_name || "PRV House Item";
  const hasContact = !!(item?.owner_name || item?.owner_phone || item?.owner_address);
  const message = item
    ? `Please return it to the owner${item.owner_name ? ` ${esc(item.owner_name)}` : ""}. Thank you for your honesty!`
    : "This item belongs to a PRV House user. If you found or borrowed it, please try to return it to its owner.";
  const brand = `<svg width="22" height="22" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" fill="white" d="M18 10 h28 v80 h-28 Z M46 10 L68 10 Q90 10 90 33 Q90 56 68 56 L46 56 Z M46 26 L65 26 Q74 26 74 33 Q74 40 65 40 L46 40 Z"/></svg>`;
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(itemName)} · PRV House</title></head>
<body style="margin:0;min-height:100dvh;background:#0d1117;color:#f0f6ff;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;display:flex;align-items:center;justify-content:center;padding:20px;box-sizing:border-box">
<div style="background:rgba(255,255,255,0.07);border:1px solid rgba(255,255,255,0.12);border-radius:24px;padding:32px;max-width:400px;width:100%">
  <div style="display:flex;align-items:center;gap:10px;margin-bottom:24px">
    <div style="width:34px;height:34px;border-radius:9px;background:#0D1420;display:flex;align-items:center;justify-content:center">${brand}</div>
    <span style="font-size:11px;color:rgba(255,255,255,0.35);letter-spacing:1px;text-transform:uppercase">PRV House</span>
  </div>
  <div style="width:64px;height:64px;border-radius:18px;background:rgba(255,140,0,0.15);display:flex;align-items:center;justify-content:center;margin-bottom:16px;font-size:28px">📦</div>
  <h1 style="font-size:26px;font-weight:700;margin:0 0 4px">${esc(itemName)}</h1>
  ${item?.property_name ? `<p style="font-size:13px;color:rgba(255,255,255,0.4);margin:0 0 24px">${esc(item.property_name)}</p>` : ""}
  <div style="background:rgba(255,140,0,0.1);border:1px solid rgba(255,140,0,0.28);border-radius:14px;padding:16px 18px;margin:18px 0 22px">
    <h2 style="font-size:14px;font-weight:600;color:#ffaa44;margin:0 0 6px">Found or Borrowed This Item?</h2>
    <p style="font-size:13px;color:rgba(255,255,255,0.65);line-height:1.55;margin:0">${message}</p>
  </div>
  ${hasContact ? `<div style="background:rgba(255,255,255,0.04);border-radius:14px;overflow:hidden">
    ${row("Owner", item?.owner_name)}
    ${row("Phone", item?.owner_phone, item?.owner_phone ? `tel:${item.owner_phone}` : undefined)}
    ${row("Address", item?.owner_address)}
  </div>` : ""}
  <p style="font-size:11px;color:rgba(255,255,255,0.18);text-align:center;margin-top:28px">Powered by PRV House · Home Management</p>
</div></body></html>`;
}
