import SwiftUI
import Supabase

// MARK: - Active Sessions Sheet
//
// Real data: rows come from `device_sessions` via DeviceSessionService —
// this device registers itself on appear (heartbeat), the rest is whatever
// the registry honestly contains. Removing a device deletes its registry
// row; only "Sign out all other sessions" (auth scope .others) actually
// invalidates tokens, and the copy says exactly that.

struct ActiveSessionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var service: DeviceSessionService { .shared }
    @State private var isLoading = true
    @State private var sessionToRevoke: DeviceSession?

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                content
            }
            .navigationTitle("Active sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.blue)
                }
            }
        }
        .task {
            await service.registerCurrentDevice()
            await service.load()
            isLoading = false
        }
        .confirmationDialog(
            "Remove this device?",
            isPresented: Binding(
                get: { sessionToRevoke != nil },
                set: { if !$0 { sessionToRevoke = nil } }
            ),
            titleVisibility: .visible,
            presenting: sessionToRevoke
        ) { session in
            Button("Remove device", role: .destructive) {
                Task { await service.revoke(session) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the device from the registry. It does not sign the device out — use \"Sign out all other sessions\" for that.")
        }
    }

    // MARK: Content states

    @ViewBuilder
    private var content: some View {
        if isLoading && service.sessions.isEmpty {
            ProgressView()
        } else if service.sessions.isEmpty {
            EmptyStateView(
                icon: "iphone.slash",
                title: "No active sessions",
                message: "Devices appear here after they sign in to your account."
            )
            .padding(.horizontal, AppSpacing.xl)
        } else {
            sessionList
        }
    }

    private var sessionList: some View {
        let sessions = orderedSessions
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    sessionRow(session)
                    if session.id != sessions.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .liquidGlass(cornerRadius: AppRadius.xl)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)

            Text("Removing a device only clears it from this list. \"Sign out all other sessions\" actually invalidates their access.")
                .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.38))
                .multilineTextAlignment(.center).padding(.horizontal, 28).padding(.top, AppSpacing.lg)

            Button {
                Task { try? await supabase.auth.signOut(scope: .others) }
            } label: {
                Text("Sign out all other sessions")
                    .font(AppFont.footnoteEmphasis).foregroundStyle(.red)
                    .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.base)
                    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.xl)
        }
    }

    /// Current device pinned first; the rest keep the service's
    /// last-seen-descending order.
    private var orderedSessions: [DeviceSession] {
        service.sessions.sorted { a, b in
            let aCurrent = a.deviceId == service.currentDeviceId
            let bCurrent = b.deviceId == service.currentDeviceId
            if aCurrent != bCurrent { return aCurrent }
            return a.lastSeenAt > b.lastSeenAt
        }
    }

    // MARK: Row

    private func sessionRow(_ session: DeviceSession) -> some View {
        let isCurrent = session.deviceId == service.currentDeviceId
        return HStack(spacing: 12) {
            ColoredIconBadge(icon: Self.icon(for: session.model),
                             color: isCurrent ? Color.brandSuccess : Color.brandPrimaryBlue)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.deviceName ?? session.model ?? session.deviceId)
                        .font(AppFont.scaled(15)).foregroundStyle(.primary)
                        .lineLimit(1)
                    if isCurrent {
                        Text("CURRENT")
                            .font(AppFont.scaled(9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, AppSpacing.xs).padding(.vertical, 2)
                            .background(Color.brandSuccess, in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    if let model = session.model, session.deviceName != nil {
                        Text(verbatim: model)
                        Text(verbatim: "·")
                    }
                    lastSeenText(session)
                }
                .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(0.4))
            }
            Spacer()
            if !isCurrent {
                Button {
                    sessionToRevoke = session
                } label: {
                    Image(systemName: "trash")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(Color.brandDanger)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove device"))
            }
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 13)
    }

    // MARK: Last seen — "Active now" under 5 minutes, relative beyond

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .named
        return f
    }()

    private func lastSeenText(_ session: DeviceSession) -> Text {
        guard let date = session.lastSeenDate else {
            return Text(verbatim: "—")
        }
        if Date().timeIntervalSince(date) < 5 * 60 {
            return Text("Active now")
        }
        return Text(Self.relative.localizedString(for: date, relativeTo: Date()))
    }

    private static func icon(for model: String?) -> String {
        guard let model else { return "iphone" }
        if model.localizedCaseInsensitiveContains("ipad") { return "ipad" }
        if model.localizedCaseInsensitiveContains("mac") { return "laptopcomputer" }
        return "iphone"
    }
}

// MARK: - Export Item

struct ExportItem: Identifiable {
    let id = UUID()
    let url: URL
}
