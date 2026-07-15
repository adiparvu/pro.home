import Foundation
import Supabase

/// The project's publishable (anon) API key.
let supabasePublishableKey = "sb_publishable_2gO8iM7dBqlbQqCiSTFeLQ_CV-DBgnC"

// Auth uses the IMPLICIT flow, not the default PKCE. Invite / magic-link emails
// are initiated server-side, so this device never stored a PKCE code-verifier;
// a `?code=` callback could never be exchanged. Implicit returns the tokens in
// the URL fragment, which `auth.session(from:)` consumes directly. The app has
// no OAuth flows, so this is safe.
//
// Realtime authenticates with the PUBLISHABLE (anon) key, NOT the user's
// session JWT. This project signs user JWTs with ES256 (Supabase's new
// asymmetric signing keys — the `sb_publishable_` key format), which this
// project's Realtime service rejects with `JwtSignatureError` on channel join.
// That made EVERY realtime channel fail to subscribe ("Maximum retry attempts
// reached") and flood the tenant into a rate limit — killing chat typing and
// live delivery. All of the app's live chat features ride on PUBLIC broadcast
// channels that need no user identity, so joining with the anon key makes them
// work; the RealtimeClientV2 consults this closure first for every token fetch
// (see RealtimeClientV2.accessTokenValue), so it authoritatively wins over the
// SDK's automatic session-token propagation. RLS-gated postgres_changes stay
// anon (already the case while joins were being rejected).
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://kwcanenheihuylaymwsl.supabase.co")!,
    supabaseKey: supabasePublishableKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(flowType: .implicit),
        realtime: RealtimeClientOptions(
            accessToken: { supabasePublishableKey }
        )
    )
)
