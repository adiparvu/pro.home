# parcels-inbound (Cloudflare Email Worker)

Receives all mail sent to `*@parcelsprv.com` (catch-all) and forwards the raw
message to the `email-inbound` Supabase Edge Function, which parses it, extracts
the tracking number, creates the delivery and registers it with Ship24.

Deployed to the Cloudflare account's `parcels-inbound` Worker, bound as the
Email Routing catch-all action for the `parcelsprv.com` zone.

Gmail's forwarding-confirmation emails are forwarded to the owner's real inbox
(`MY_EMAIL`) so the forward can be approved. The `?secret=` in `INBOUND_URL`
must match the `EMAIL_INBOUND_SECRET` Supabase secret.
