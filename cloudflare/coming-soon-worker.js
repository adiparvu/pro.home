// coming-soon — Cloudflare Worker serving the holding page for xparvu.com.
//
// Route: xparvu.com/* (and www.xparvu.com/*) — the catch-all. The item QR
// pages keep their own worker on the MORE SPECIFIC route xparvu.com/i/*,
// which Cloudflare always prefers, so /i/<uuid> is untouched.
//
// Fully self-contained: no assets, no JS frameworks — pure CSS animation
// (aurora gradient drift, floating brand mark, shimmer progress), honest
// about respecting prefers-reduced-motion. One extra note: the domain
// listens to serious offers — five zeros minimum (€100.000+).

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
<meta name="description" content="PRVIO — premium home &amp; property management. Under construction.">
<title>PRVIO — În lucru · Under construction</title>
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
  .aurora { position: fixed; inset: -20%; filter: blur(90px); opacity: .5; z-index: 0; }
  .aurora span { position: absolute; border-radius: 50%; }
  .aurora span:nth-child(1) {
    width: 55vmax; height: 55vmax; left: -10%; top: -15%;
    background: radial-gradient(circle, #1c3f8f 0%, transparent 65%);
    animation: drift1 26s ease-in-out infinite alternate;
  }
  .aurora span:nth-child(2) {
    width: 45vmax; height: 45vmax; right: -12%; top: 20%;
    background: radial-gradient(circle, #5b2a86 0%, transparent 65%);
    animation: drift2 32s ease-in-out infinite alternate;
  }
  .aurora span:nth-child(3) {
    width: 40vmax; height: 40vmax; left: 25%; bottom: -20%;
    background: radial-gradient(circle, #0d5c63 0%, transparent 65%);
    animation: drift3 38s ease-in-out infinite alternate;
  }
  @keyframes drift1 { to { transform: translate(12vmax, 8vmax) scale(1.15); } }
  @keyframes drift2 { to { transform: translate(-10vmax, -6vmax) scale(0.9); } }
  @keyframes drift3 { to { transform: translate(-8vmax, -10vmax) scale(1.2); } }

  /* Faint star field via two box-shadow layers. */
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
    padding: 48px 32px; max-width: 520px; width: calc(100% - 40px);
    background: rgba(255,255,255,.045);
    border: 1px solid rgba(255,255,255,.1);
    border-radius: 28px;
    backdrop-filter: blur(22px); -webkit-backdrop-filter: blur(22px);
    box-shadow: 0 30px 80px rgba(0,0,0,.45);
  }

  .mark {
    width: 76px; height: 76px; margin: 0 auto 22px; border-radius: 20px;
    background: #0D1420; display: flex; align-items: center; justify-content: center;
    border: 1px solid rgba(255,255,255,.12);
    animation: float 5s ease-in-out infinite;
    box-shadow: 0 12px 40px rgba(28,63,143,.45);
  }
  @keyframes float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-9px); } }

  h1 {
    font-size: 44px; font-weight: 800; letter-spacing: 6px; margin-bottom: 6px;
    background: linear-gradient(100deg, #f0f6ff 20%, #7ea6ff 45%, #f0f6ff 70%);
    background-size: 200% 100%;
    -webkit-background-clip: text; background-clip: text; color: transparent;
    animation: sheen 5.5s linear infinite;
  }
  @keyframes sheen { to { background-position: -200% 0; } }

  .tag { font-size: 14px; color: rgba(240,246,255,.55); letter-spacing: .4px; margin-bottom: 26px; }

  .status {
    display: inline-flex; align-items: center; gap: 10px;
    font-size: 13px; font-weight: 600; letter-spacing: 1.6px; text-transform: uppercase;
    color: #8fd3a8; background: rgba(74,222,128,.09);
    border: 1px solid rgba(74,222,128,.25);
    padding: 9px 18px; border-radius: 999px; margin-bottom: 26px;
  }
  .dot { width: 8px; height: 8px; border-radius: 50%; background: #4ade80;
         animation: pulse 1.8s ease-in-out infinite; }
  @keyframes pulse { 0%,100% { box-shadow: 0 0 0 0 rgba(74,222,128,.5); }
                     50% { box-shadow: 0 0 0 7px rgba(74,222,128,0); } }

  .bar { height: 4px; border-radius: 999px; overflow: hidden;
         background: rgba(255,255,255,.08); margin: 0 auto 30px; max-width: 300px; }
  .bar i { display: block; height: 100%; width: 40%; border-radius: 999px;
           background: linear-gradient(90deg, transparent, #7ea6ff, transparent);
           animation: slide 2.4s ease-in-out infinite; }
  @keyframes slide { from { transform: translateX(-110%); } to { transform: translateX(850%); } }

  .sale {
    font-size: 12.5px; line-height: 1.65; color: rgba(240,246,255,.42);
    border-top: 1px solid rgba(255,255,255,.08); padding-top: 20px;
  }
  .sale strong { color: rgba(240,246,255,.75); font-weight: 600; }

  @media (prefers-reduced-motion: reduce) {
    .aurora span, .stars, .stars::after, .mark, h1, .dot, .bar i { animation: none; }
  }
</style></head>
<body>
<div class="aurora" aria-hidden="true"><span></span><span></span><span></span></div>
<div class="stars" aria-hidden="true"></div>
<main class="card">
  <div class="mark" aria-hidden="true">
    <svg width="38" height="38" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" fill="white" d="M18 10 h28 v80 h-28 Z M46 10 L68 10 Q90 10 90 33 Q90 56 68 56 L46 56 Z M46 26 L65 26 Q74 26 74 33 Q74 40 65 40 L46 40 Z"/></svg>
  </div>
  <h1>PRVIO</h1>
  <p class="tag">Premium home &amp; property management</p>
  <div class="status"><span class="dot"></span>În lucru · Under construction</div>
  <div class="bar" aria-hidden="true"><i></i></div>
  <p class="sale">Interested in this domain? <strong>Serious offers only — think five zeros: €100.000+</strong></p>
</main>
</body></html>`;
