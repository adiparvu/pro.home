// coming-soon — Cloudflare Worker serving the holding page for xparvu.com.
//
// Route: xparvu.com/* (and www.xparvu.com/*) — the catch-all. The item QR
// pages keep their own worker on the MORE SPECIFIC route xparvu.com/i/*,
// which Cloudflare always prefers, so /i/<uuid> is untouched.
//
// Deliberately brandless (IMG_8661): the domain page has nothing to do with
// the app — just a bobbing hard hat, "Under construction", and the sale note
// (€500.000). Self-contained, pure CSS animation, quiet under
// prefers-reduced-motion.

export default {
  async fetch() {
    return new Response(PAGE, {
      headers: {
        "content-type": "text/html; charset=utf-8",
        "cache-control": "public, max-age=300",
      },
    });
  },
};

const PAGE = `<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="Under construction.">
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
  .sale strong { color: rgba(240,246,255,.8); font-weight: 600; }

  @media (prefers-reduced-motion: reduce) {
    .aurora span, .stars, .stars::after, .hat, h1, .bar i { animation: none; }
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
  <p class="sale">Interested in this domain? <strong>€500.000</strong></p>
</main>
</body></html>`;
