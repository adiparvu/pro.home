import SwiftUI
import UIKit

// MARK: - Sensor webhook setup (Smart Control R4)
//
// The full setup surface for the per-account iot-event webhook (the hub's
// automations tab keeps its quick copy card; this page is the place that
// explains everything): the POST address with the account's secret, the
// secret itself behind a reveal control (treated like a password), and a
// copy-paste example payload.
//
// Every fact shown here is verified against the deployed function's source
// (supabase/functions/iot-event): the endpoint is `IoTService.eventEndpoint`
// with `?token=<secret>`, the body is JSON with sensorId / name / type /
// event ("alert" | "clear") / value / unit / zone / display, "alert" sends
// a push, "clear" ends the alert's Live Activity, and every event is
// persisted into the sensor's history. The secret row is created on first
// open when none exists (`IoTService.ensureWebhook`).

struct IoTWebhookSetupView: View {
    @State private var service = IoTService.shared

    private enum Phase { case preparing, ready, failed }
    @State private var phase: Phase = .preparing
    @State private var secretRevealed = false
    @State private var copied: String? = nil
    @State private var copyResetTask: Task<Void, Never>? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                heroCard
                switch phase {
                case .preparing: preparingState
                case .failed:    failedState
                case .ready:     readyContent
                }
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("iot_wh_title"))
        .navigationBarTitleDisplayMode(.large)
        .task { await prepare() }
        .onDisappear { copyResetTask?.cancel() }
    }

    private func prepare() async {
        phase = .preparing
        await service.ensureWebhook()
        phase = service.webhookURL != nil ? .ready : .failed
    }

    // MARK: Hero — what this is, honestly

    private var heroCard: some View {
        HStack(alignment: .top, spacing: AppSpacing.base) {
            ColoredIconBadge(icon: "dot.radiowaves.up.forward",
                             color: Color.brandPurple, size: 40)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("iot_wh_title")
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                Text("iot_wh_page_caption")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    // MARK: Ready — URL, secret, example

    @ViewBuilder private var readyContent: some View {
        if let url = service.webhookURL, let secret = service.webhookSecret {
            urlRow(url: url, secret: secret)

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                secretRow(secret: secret)
                Text("iot_wh_secret_caption")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, AppSpacing.xxs)
            }

            exampleSection
        }
    }

    /// The full POST address — the secret token in it stays masked on
    /// screen; copying yields the real, ready-to-paste URL.
    private func urlRow(url: URL, secret: String) -> some View {
        let shown = url.absoluteString.replacingOccurrences(
            of: secret, with: Self.masked(secret))
        return copyRow(icon: "link", tint: Color.brandPrimaryBlue,
                       titleKey: "iot_wh_url_title",
                       shownValue: shown,
                       copyValue: url.absoluteString,
                       copyKey: "url")
    }

    private func secretRow(secret: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            ColoredIconBadge(icon: "key.fill", color: Color.brandWarning, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("iot_wh_secret_title")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                Text(verbatim: secretRevealed ? secret : Self.masked(secret))
                    .font(AppFont.scaled(12, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: AppSpacing.sm)
            Button {
                HapticFeedback.selection()
                withAnimation(.smooth(duration: 0.2)) { secretRevealed.toggle() }
            } label: {
                Image(systemName: secretRevealed ? "eye.slash" : "eye")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(secretRevealed ? "iot_wh_hide" : "iot_wh_reveal"))
            copyButton(value: secret, key: "secret")
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    // MARK: Example payload (format verified against the deployed function)

    /// The documented body shape of the iot-event function — locale-neutral
    /// sample values, real field names.
    private static let examplePayload = """
    {
      "sensorId": "senzor-living",
      "name": "Senzor living",
      "type": "temperature",
      "event": "alert",
      "value": 23.5,
      "unit": "°C",
      "zone": "Living"
    }
    """

    private var exampleSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("iot_wh_example_title")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)

            Button {
                UIPasteboard.general.string = Self.examplePayload
                markCopied("example")
            } label: {
                HStack(alignment: .top, spacing: AppSpacing.sm) {
                    Text(verbatim: Self.examplePayload)
                        .font(AppFont.scaled(12, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: copied == "example" ? "checkmark" : "doc.on.doc")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(copied == "example"
                                         ? Color.brandSuccess : Color.accentColor)
                }
                .padding(AppSpacing.base)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .liquidGlass(cornerRadius: AppRadius.lg)
            .accessibilityLabel(Text("iot_wh_example_title"))
            .accessibilityHint(Text(copied == "example" ? "iot_wh_copied" : "iot_wh_copy"))

            Text("iot_wh_example_caption")
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, AppSpacing.xxs)
        }
    }

    // MARK: Honest preparing / failed states

    private var preparingState: some View {
        HStack(spacing: AppSpacing.md) {
            ProgressView()
            Text("iot_wh_preparing")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    private var failedState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("iot_wh_failed")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                HapticFeedback.impact(.light)
                Task { await prepare() }
            } label: {
                Label("iot_wh_retry", systemImage: "arrow.clockwise")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(AppSpacing.lg)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    // MARK: Shared row + copy plumbing

    private func copyRow(icon: String, tint: Color, titleKey: LocalizedStringKey,
                         shownValue: String, copyValue: String,
                         copyKey: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            ColoredIconBadge(icon: icon, color: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                Text(verbatim: shownValue)
                    .font(AppFont.scaled(12, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: AppSpacing.sm)
            copyButton(value: copyValue, key: copyKey)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }

    private func copyButton(value: String, key: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            markCopied(key)
        } label: {
            Image(systemName: copied == key ? "checkmark" : "doc.on.doc")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(copied == key ? Color.brandSuccess : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(copied == key ? "iot_wh_copied" : "iot_wh_copy"))
    }

    private func markCopied(_ key: String) {
        HapticFeedback.success()
        withAnimation(.smooth(duration: 0.2)) { copied = key }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.2)) { copied = nil }
        }
    }

    /// "3f2a91b4••••••••" — enough to recognize, never enough to use.
    private static func masked(_ secret: String) -> String {
        String(secret.prefix(8)) + "••••••••"
    }
}
