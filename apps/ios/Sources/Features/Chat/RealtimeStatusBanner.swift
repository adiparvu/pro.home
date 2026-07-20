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

    /// Fully healthy: socket connected, channel subscribed, broadcast echoed.
    private var isLive: Bool { status == "live" }
    /// Still resolving the first subscribe (or stuck retrying).
    private var isConnecting: Bool { status == "…" }
    private var tint: Color {
        if isLive { return Color.brandSuccess }
        if isConnecting { return Color.secondaryTextColor }
        return Color.brandWarning
    }

    // NOTE: temporarily ALWAYS visible — green when live, grey while connecting,
    // orange when degraded — so the exact realtime state is never blank while
    // the typing/delivery fault is being diagnosed. A blank (hidden) banner
    // during a stuck "…" retry is exactly what made it look absent. Reverts to
    // warning-only once resolved.
    var body: some View {
        Group {
            Button {
                // Export the WHOLE flight recorder, not just the one-line
                // status: transitions + SDK close codes + watchdog events —
                // one paste pinpoints the failing layer.
                UIPasteboard.general.string = "\(status)\n\n\(RealtimeFlightRecorder.shared.fullLog)"
                HapticFeedback.impact(.light)
                withAnimation(.snappy) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.snappy) { copied = false }
                }
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: isLive ? "checkmark.seal.fill"
                        : isConnecting ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill")
                    Text("\(String(localized: "realtime_status_prefix")): \(status)")
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Spacer(minLength: AppSpacing.xs)
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                }
                .font(AppFont.caption2)
                .foregroundStyle(tint)
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.opacity(0.12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(String(localized: "realtime_status_prefix")): \(status)"))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
