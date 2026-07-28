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

// MARK: - The app's ONE realtime client (standalone, deliberately)
//
// EVERY realtime channel in the app goes through `realtimeAnon`, never
// `supabase.realtimeV2`. A standalone client keeps channel auth EXPLICIT: the
// main SupabaseClient's internal auth→realtime wiring (`listenForAuthEvents` →
// `setAuth`) never touches it, so what rides each join is exactly what the
// `accessToken` closure below returns — nothing races it.
//
// AUTH MODEL (verified headlessly against THIS project's Realtime, 2026-07-16):
//  - Handshake identity: the publishable key (apikey query/header). Constant.
//  - Channel credential: the user's SESSION JWT when signed in, falling back
//    to the publishable key when signed out. The SDK calls the closure on
//    every join and pushes `access_token` refreshes over the socket, so token
//    rotation is handled.
//  - The user JWT is REQUIRED for delivery, not just accepted: RLS-protected
//    postgres_changes (messages rows are member-only) deliver rows
//    per the subscriber's claims — an anon subscription is accepted but every
//    row is withheld. Migration 156's realtime authorization policies are
//    also granted TO authenticated.
//  - An earlier build concluded the ES256 JWT was rejected on join
//    ("JwtSignatureError") and forced the anon key here. That conclusion was
//    contaminated by the v1-framing bug below (an undecodable reply and a
//    rejected join look identical from the app). Re-proven 2026-07-16 with a
//    real ES256 session JWT: join ok, "Subscribed to PostgreSQL" ok,
//    broadcast echo ok.
//
// PROTOCOL VERSION — leave it at the library default (`.v2`, protocol 2.0.0).
// An earlier build pinned `vsn: .v1`, believing the server was broken on v2 —
// that was WRONG and was itself a regression. supabase-swift's
// `RealtimeSerializer` implements ONLY protocol 2.0.0 (array framing); forcing
// v1 makes the server reply in object framing the client can't decode, so
// every subscribe times out to maxRetry even though the socket is healthy.
//
// CONNECTION LIFETIME — `RealtimeFlightRecorder.startWatchdog()` (called from
// MainTabView) owns connect/reconnect. The SDK's auto-reconnect is ONE-SHOT:
// a dropped socket schedules a single retry, and if that attempt fails the
// client parks in `.disconnected` forever. The watchdog revives it.
let realtimeAnon = RealtimeClientV2(
    url: URL(string: "https://kwcanenheihuylaymwsl.supabase.co/realtime/v1")!,
    options: RealtimeClientOptions(
        headers: [
            "apikey": supabasePublishableKey,
            "Authorization": "Bearer \(supabasePublishableKey)"
        ],
        // Session JWT when signed in (RLS-scoped postgres_changes delivery +
        // migration 156's authenticated-only realtime authorization);
        // publishable key when signed out. `auth.session` refreshes an
        // expired token before returning, so joins never carry a stale JWT.
        //
        // NEVER downgrade a signed-in user to the publishable key: the same
        // network blip that drops the socket also fails `auth.session` here,
        // and an anon-key join on authenticated-only broadcast/presence is
        // CONFIRMED then CLOSED by the server — the b1157 field log's
        // "subscribed → phx_close" storm, killing exactly the broadcast
        // channels (messages, dm_*) while postgres-only ones survived. The
        // cached session token is the same identity and usually still valid;
        // the publishable key is strictly the signed-out credential.
        accessToken: {
            if let live = try? await supabase.auth.session { return live.accessToken }
            return supabase.auth.currentSession?.accessToken ?? supabasePublishableKey
        },
        // Flight recorder: SDK-internal close codes and reconnect decisions
        // land in the same timeline the diagnostic banner exports.
        logger: RealtimeFlightRecorder.shared
    )
)
