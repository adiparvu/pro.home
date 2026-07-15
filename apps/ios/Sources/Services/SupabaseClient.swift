import Foundation
import Supabase

/// The project's publishable (anon) API key.
let supabasePublishableKey = "sb_publishable_2gO8iM7dBqlbQqCiSTFeLQ_CV-DBgnC"

// Auth uses the IMPLICIT flow, not the default PKCE. Invite / magic-link emails
// are initiated server-side, so this device never stored a PKCE code-verifier;
// a `?code=` callback could never be exchanged. Implicit returns the tokens in
// the URL fragment, which `auth.session(from:)` consumes directly. The app has
// no OAuth flows, so this is safe.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://kwcanenheihuylaymwsl.supabase.co")!,
    supabaseKey: supabasePublishableKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(flowType: .implicit)
    )
)

// MARK: - Realtime authenticates with the ANON key, via a STANDALONE client
//
// This project signs user JWTs with ES256 (Supabase's new asymmetric keys — the
// `sb_publishable_` key format), which this project's Realtime service rejects
// with `JwtSignatureError` on channel join. Proven both ways: a headless anon-key
// websocket join succeeds instantly, and the app failed with "Maximum retry
// attempts reached".
//
// The subtle trap: setting `RealtimeClientOptions(accessToken:)` on the MAIN
// SupabaseClient is NOT enough. Because `AuthOptions.accessToken` is nil, the
// SDK runs `listenForAuthEvents()` and, on every initialSession/signedIn/
// tokenRefreshed, calls `realtimeV2.setAuth(sessionJWT)` — which overwrites the
// stored token and PUSHES the ES256 JWT onto already-subscribed channels
// (`access_token` event), so the channel joins with the anon key, then gets
// killed the instant auth propagates. That is the intermittent "subscribed then
// dead / maxRetry" we saw (verified against supabase-swift v2.51 source).
//
// The only leak-proof fix that keeps PostgREST/Storage/Functions on the user's
// authed JWT (for RLS) is a SEPARATE RealtimeClientV2 that the SupabaseClient's
// auth→realtime wiring never touches. Nothing ever calls setAuth(jwt) on it, so
// every join carries the anon key and nothing overrides it. All of the app's
// realtime rides on PUBLIC broadcast + property-scoped channels that need no
// user identity, so the anon key is the correct and sufficient credential.
//
// EVERY realtime channel in the app goes through `realtimeAnon`, never
// `supabase.realtimeV2`.
//
// PROTOCOL VERSION — leave it at the library default (`.v2`, protocol 2.0.0).
//
// This was the real cause of the persistent "Maximum retry attempts reached".
// An earlier build pinned `vsn: .v1`, believing the server was broken on v2 —
// that was WRONG and was itself the regression. supabase-swift 2.51's
// `RealtimeSerializer` implements ONLY protocol 2.0.0: it encodes every frame
// as a JSON array `[joinRef, ref, topic, event, payload]` and its `decodeText`
// can ONLY parse that array shape. Forcing `vsn=1.0.0` makes the server reply
// in 1.0.0 OBJECT framing (`{"topic":…,"event":…}`), which the client's
// array-only decoder throws on — so the join reply is never matched, every
// subscribe times out, and the channel retries to exhaustion (`maxRetry`),
// even though the socket connected fine.
//
// Proven headlessly against THIS project's Realtime, over vsn=2.0.0, with the
// exact channels the app opens (broadcast + postgres_changes) and the anon key
// in both the `Authorization` header and the join's `access_token`: the join
// is accepted (`status: ok`, "Subscribed to PostgreSQL") and a `self:true`
// broadcast round-trips. So the default v2 is exactly what this server serves —
// the client simply has to speak its own native protocol.
let realtimeAnon = RealtimeClientV2(
    url: URL(string: "https://kwcanenheihuylaymwsl.supabase.co/realtime/v1")!,
    options: RealtimeClientOptions(
        headers: [
            "apikey": supabasePublishableKey,
            "Authorization": "Bearer \(supabasePublishableKey)"
        ],
        accessToken: { supabasePublishableKey }
    )
)
