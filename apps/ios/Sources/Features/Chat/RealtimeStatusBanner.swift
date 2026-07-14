import SwiftUI
import UIKit

/// A thin, unobtrusive diagnostic strip pinned to the top of a chat's message
/// list. It stays completely hidden while realtime is healthy and only surfaces
/// when the WebSocket subscription is degraded — showing the exact live status
/// string (including the verbatim subscribe error) so it can be screenshotted.
/// Tapping the strip copies the full text to the clipboard for a bug report.
///
/// This is a debug / error surface, not chrome: the dynamic status is
/// intentionally verbatim (raw error text, never localized). Only the fixed
/// "Realtime" prefix is localized. When the service reports `"live"` — or the
/// initial `"…"` placeholder before the first subscribe resolves — the view
/// renders nothing and reserves no layout space.
struct RealtimeStatusBanner: View {
    /// The service's `realtimeStatus` snapshot (e.g. `"live"`,
    /// `"socket:disconnected chan:none"`, `"FAIL: <error> · socket:…"`).
    let status: String

    @State private var copied = false

    /// Healthy or still-connecting states hide the banner entirely.
    private var isHidden: Bool { status == "live" || status == "…" }

    var body: some View {
        if !isHidden {
            Button {
                UIPasteboard.general.string = status
                HapticFeedback.impact(.light)
                withAnimation(.snappy) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.snappy) { copied = false }
                }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("\(String(localized: "realtime_status_prefix")): \(status)")
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer(minLength: AppSpacing.xs)
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                }
                .font(AppFont.caption2)
                .foregroundStyle(Color.brandWarning)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandWarning.opacity(0.12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(String(localized: "realtime_status_prefix")): \(status)"))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
