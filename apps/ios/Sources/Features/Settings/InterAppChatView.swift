import SwiftUI

// MARK: - Cross-app messaging screen
//
// Manages a property's inbound channel (on/off, token rotation, live test).
// All channel state and database access live in CrossAppChannelService —
// this screen is presentation only.

struct InterAppChatView: View {
    @Environment(PropertyService.self) private var propertyService

    @State private var service = CrossAppService()
    @State private var testState: TestState = .idle
    @State private var copied: String?

    private enum TestState { case idle, running, ok, failed }

    private var propertyId: UUID? { propertyService.primary?.id }
    private var enabled: Bool { service.channel?.enabled ?? false }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {

                // Master switch
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { enabled },
                        set: { on in
                            guard let pid = propertyId else { return }
                            Task { await service.setEnabled(on, propertyId: pid) }
                        }
                    ).animation(AppMotion.state)) {
                        Text("Enable")
                            .font(AppFont.scaled(17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                    .liquidGlass(cornerRadius: AppRadius.lg)

                    Text("Lets other apps and services send messages into your house chat.")
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .padding(.horizontal, AppSpacing.xs)
                }

                if enabled, let channel = service.channel {
                    // Endpoint + token
                    VStack(alignment: .leading, spacing: 10) {
                        Text("CONNECTION")
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .padding(.leading, AppSpacing.xxs)

                        copyRow(icon: "link", tint: .blue, title: "Endpoint",
                                value: CrossAppService.endpoint.absoluteString, key: "url")
                        copyRow(icon: "key.fill", tint: .orange, title: "Secret token",
                                value: channel.token.uuidString.lowercased(), key: "token", masked: true)

                        Button {
                            guard let pid = propertyId else { return }
                            HapticFeedback.impact(.medium)
                            Task { await service.regenerateToken(propertyId: pid) }
                        } label: {
                            Label("Rotate token", systemImage: "arrow.triangle.2.circlepath")
                                .font(AppFont.captionEmphasis)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, AppSpacing.xxs)

                        Text("Any app that can send a POST request can deliver messages: Shortcuts automations, Zapier, IFTTT, a home server. Rotating the token instantly disconnects everything using the old one.")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xs)
                    }

                    // Payload example
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MESSAGE FORMAT")
                            .font(AppFont.label)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            .padding(.leading, AppSpacing.xxs)
                        let sample = "{\n  \"token\": \"\(channel.token.uuidString.lowercased())\",\n  \"sender\": \"Aria\",\n  \"text\": \"Salut din altă aplicație!\"\n}"
                        Text(sample)
                            .font(AppFont.scaled(12, design: .monospaced))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppSpacing.base)
                            .liquidGlass(cornerRadius: AppRadius.lg)
                            .onTapGesture {
                                UIPasteboard.general.string = sample
                                copied = "sample"
                                HapticFeedback.selection()
                            }
                        if copied == "sample" {
                            Label("Copied", systemImage: "checkmark")
                                .font(AppFont.scaled(11)).foregroundStyle(Color.brandSuccess)
                                .padding(.leading, AppSpacing.xxs)
                        }
                    }

                    // Live test
                    Button {
                        testState = .running
                        Task {
                            let ok = await service.sendTest()
                            testState = ok ? .ok : .failed
                            if ok { HapticFeedback.success() } else { HapticFeedback.warning() }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            switch testState {
                            case .running: ProgressView()
                            case .ok:      Image(systemName: "checkmark.circle.fill")
                            case .failed:  Image(systemName: "xmark.circle.fill")
                            case .idle:    Image(systemName: "paperplane.fill")
                            }
                            Text(testState == .ok ? "Sent — check the chat!" : "Send test message")
                                .font(AppFont.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(testState == .running ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                        .glassProminent(in: Capsule(), enabled: testState != .running)
                    }
                    .buttonStyle(.plain)
                    .disabled(testState == .running)

                    // Requests toggle
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: Binding(
                            get: { service.channel?.notifyRequests ?? true },
                            set: { on in
                                guard let pid = propertyId else { return }
                                Task { await service.setNotifyRequests(on, propertyId: pid) }
                            }
                        )) {
                            Text("Notify on external messages")
                                .font(AppFont.scaled(16))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                        .liquidGlass(cornerRadius: AppRadius.lg)

                        Text("External messages appear in chat marked with ⥂ and the sender's app name.")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xs)
                    }

                    // Named integrations and the Shortcuts/Zapier/IoT recipes
                    // live on the Integrations page — this screen stays focused
                    // on the shared inbound channel itself.
                }

                if let err = service.error {
                    Text(err).font(AppFont.scaled(12)).foregroundStyle(.red)
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Cross-app messaging")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if let pid = propertyId { await service.load(propertyId: pid) }
        }
    }

    private func copyRow(icon: String, tint: Color, title: LocalizedStringKey,
                         value: String, key: String, masked: Bool = false) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: icon, color: tint, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.captionEmphasis).foregroundStyle(.primary)
                Text(masked ? String(value.prefix(8)) + "••••••••" : value)
                    .font(AppFont.scaled(12, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = value
                copied = key
                HapticFeedback.selection()
            } label: {
                Image(systemName: copied == key ? "checkmark" : "doc.on.doc")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(copied == key ? Color.brandSuccess : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied == key ? Text("Copied") : Text("Copy"))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }
}
