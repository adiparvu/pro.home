import Foundation
import Supabase

// Auth uses the IMPLICIT flow, not the default PKCE. Invite / magic-link emails
// are initiated server-side, so this device never stored a PKCE code-verifier;
// a `?code=` callback could never be exchanged. Implicit returns the tokens in
// the URL fragment, which `auth.session(from:)` consumes directly. The app has
// no OAuth flows, so this is safe.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://kwcanenheihuylaymwsl.supabase.co")!,
    supabaseKey: "sb_publishable_2gO8iM7dBqlbQqCiSTFeLQ_CV-DBgnC",
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(flowType: .implicit)
    )
)
