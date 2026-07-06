import SwiftUI
import Observation

// MARK: - Cross-app messaging (real gateway)
//
// Every property gets an inbound channel: a secret token + the cross-app-inbox
// edge function. Anything that can make a POST request — a Shortcuts
// automation, Zapier/IFTTT, a home server, another app — drops messages
// straight into the house chat, delivered live over the existing realtime
// pipeline. This screen manages the channel: on/off, token rotation, and a
// one-tap live test.

@MainActor
@Observable
final class CrossAppService {
    struct Channel: Codable {
        var propertyId: UUID
        var token: UUID
        var enabled: Bool
        var notifyRequests: Bool

        enum CodingKeys: String, CodingKey {
            case propertyId = "property_id"
            case token
            case enabled
            case notifyRequests = "notify_requests"
        }
    }

    var channel: Channel?
    var isLoading = false
    var error: String?

    static let endpoint = URL(string: "https://kwcanenheihuylaymwsl.supabase.co/functions/v1/cross-app-inbox")!

    func load(propertyId: UUID) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [Channel] = try await supabase
                .from("cross_app_channels")
                .select("property_id, token, enabled, notify_requests")
                .eq("property_id", value: propertyId.uuidString)
                .execute().value
            channel = rows.first
        } catch { self.error = error.localizedDescription }
    }

    /// First enable creates the channel row (token generated server-side).
    func setEnabled(_ on: Bool, propertyId: UUID) async {
        do {
            if channel == nil, on {
                guard let uid = supabase.auth.currentSession?.user.id else { return }
                struct NewChannel: Encodable {
                    let property_id: String
                    let created_by: String
                }
                try await supabase.from("cross_app_channels")
                    .insert(NewChannel(property_id: propertyId.uuidString, created_by: uid.uuidString))
                    .execute()
            } else if channel != nil {
                try await supabase.from("cross_app_channels")
                    .update(["enabled": on])
                    .eq("property_id", value: propertyId.uuidString)
                    .execute()
            }
            await load(propertyId: propertyId)
        } catch { self.error = error.localizedDescription }
    }

    func setNotifyRequests(_ on: Bool, propertyId: UUID) async {
        do {
            try await supabase.from("cross_app_channels")
                .update(["notify_requests": on])
                .eq("property_id", value: propertyId.uuidString)
                .execute()
            channel?.notifyRequests = on
        } catch { self.error = error.localizedDescription }
    }

    /// Rotating the token instantly cuts off every service using the old one.
    func regenerateToken(propertyId: UUID) async {
        do {
            try await supabase.from("cross_app_channels")
                .update(["token": UUID().uuidString])
                .eq("property_id", value: propertyId.uuidString)
                .execute()
            await load(propertyId: propertyId)
        } catch { self.error = error.localizedDescription }
    }

    /// Posts through the PUBLIC endpoint — exactly what an external app does —
    /// so a green result proves the whole path, not just the database.
    func sendTest() async -> Bool {
        guard let token = channel?.token else { return false }
        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode([
            "token": token.uuidString.lowercased(),
            "sender": String(localized: "Test PRVIO"),
            "text": String(localized: "Cross-app messaging works! 🎉"),
        ])
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}

// MARK: - Screen

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
                PageHeader(titleKey: "Cross-app messaging")

                // Master switch
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { enabled },
                        set: { on in
                            guard let pid = propertyId else { return }
                            Task { await service.setEnabled(on, propertyId: pid) }
                        }
                    ).animation()) {
                        Text("Enable")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                    .liquidGlass(cornerRadius: AppRadius.lg)

                    Text("Lets other apps and services send messages into your house chat.")
                        .font(.system(size: 13))
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, AppSpacing.xxs)

                        Text("Any app that can send a POST request can deliver messages: Shortcuts automations, Zapier, IFTTT, a home server. Rotating the token instantly disconnects everything using the old one.")
                            .font(.system(size: 12))
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
                            .font(.system(size: 12, design: .monospaced))
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
                                .font(.system(size: 11)).foregroundStyle(Color.brandSuccess)
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
                            case .running: ProgressView().tint(.white)
                            case .ok:      Image(systemName: "checkmark.circle.fill")
                            case .failed:  Image(systemName: "xmark.circle.fill")
                            case .idle:    Image(systemName: "paperplane.fill")
                            }
                            Text(testState == .ok ? "Sent — check the chat!" : "Send test message")
                                .font(AppFont.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(colors: [Color.accentColor, Color.brandPurple],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        )
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
                                .font(.system(size: 16))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
                        .liquidGlass(cornerRadius: AppRadius.lg)

                        Text("External messages appear in chat marked with ⥂ and the sender's app name.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xs)
                    }

                    // Named integrations and the Shortcuts/Zapier/IoT recipes
                    // live on the Integrations page — this screen stays focused
                    // on the shared inbound channel itself.
                }

                if let err = service.error {
                    Text(err).font(.system(size: 12)).foregroundStyle(.red)
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
                    .font(.system(size: 12, design: .monospaced))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(copied == key ? Color.brandSuccess : Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied == key ? Text("Copied") : Text("Copy"))
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.lg)
    }
}
