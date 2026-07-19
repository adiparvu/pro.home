# item-page (Cloudflare Worker — inventory QR pages)

Serves the public "found item" page on `https://xparvu.com/i/<uuid>` — the URL
printed inside every inventory QR label. Stopgap until the full web app
(`apps/web`) is deployed behind xparvu.com; same data, same look as
`apps/web/src/app/i/[id]/page.tsx`.

Deploy (one time, ~5 minutes, Cloudflare dashboard):

1. Workers & Pages → Create → Worker, name it `item-page`, paste
   `item-page-worker.js`.
2. Settings → Variables and Secrets:
   - `SUPABASE_URL` = `https://kwcanenheihuylaymwsl.supabase.co`
   - `SUPABASE_ANON_KEY` = the **publishable (anon)** key from the Supabase
     dashboard (API settings). Never the service_role key.
3. Settings → Domains & Routes → Add route: `xparvu.com/i/*`, zone
   `xparvu.com`. Only `/i/*` goes through the worker; the rest of the domain
   is untouched.
4. Test: open an item in PRVIO → QR label → scan it. The dark "Found this
   item?" card must render; an unpublished item shows the generic card.

# parcels-inbound (Cloudflare Email Worker)

Receives all mail sent to `*@parcelsprv.com` (catch-all) and forwards the raw
message to the `email-inbound` Supabase Edge Function, which parses it, extracts
the tracking number, creates the delivery and registers it with Ship24.

Deployed to the Cloudflare account's `parcels-inbound` Worker, bound as the
Email Routing catch-all action for the `parcelsprv.com` zone.

Gmail's forwarding-confirmation emails are forwarded to the owner's real inbox
(`MY_EMAIL`) so the forward can be approved. The `?secret=` in `INBOUND_URL`
must match the `EMAIL_INBOUND_SECRET` Supabase secret.
