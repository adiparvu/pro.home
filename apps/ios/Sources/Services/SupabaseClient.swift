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
// PROTOCOL VERSION — the actual root cause of the persistent "Maximum retry
// attempts reached". supabase-swift defaults `vsn` to `.v2` (the new binary
// Realtime protocol), but THIS project's Realtime server is broken on v2:
// proven headlessly — every join/broadcast over `vsn=1.0.0` succeeds instantly
// (15/15 channels in a burst, broadcast echoes round-trip), while the v2 socket
// gets no usable join replies, so the client retries to exhaustion. It also
// explains the intermittency we chased for days: a v2 join that happened to
// reply looked "subscribed" but its broadcasts never round-tripped
// (`bcast:DEAD`), and one that didn't reply became `maxRetry`. Pinning `.v1`
// puts the whole app on the protocol this server actually serves.
let realtimeAnon = RealtimeClientV2(
    url: URL(string: "https://kwcanenheihuylaymwsl.supabase.co/realtime/v1")!,
    options: RealtimeClientOptions(
        headers: [
            "apikey": supabasePublishableKey,
            "Authorization": "Bearer \(supabasePublishableKey)"
        ],
        vsn: .v1,
        accessToken: { supabasePublishableKey }
    )
)
