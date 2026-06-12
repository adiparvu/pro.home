import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                avatar
                profileInfo
                accountSection
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Avatar

    private var avatar: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 90, height: 90)
                Text(initial)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .blue.opacity(0.4), radius: 16, y: 6)

            Text(displayName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(auth.session?.user.email ?? "")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Profile info

    private var profileInfo: some View {
        GlassCard {
            VStack(spacing: 0) {
                ProfileInfoRow(label: "Email", value: auth.session?.user.email ?? "—")
                Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 16)
                ProfileInfoRow(label: "Account ID", value: shortId)
                Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 16)
                ProfileInfoRow(label: "Member since", value: memberSince)
            }
        }
    }

    // MARK: - Account section

    private var accountSection: some View {
        SettingsGroup(title: "Account") {
            TapSettingsRow(icon: "key.fill", color: .orange, label: "Change Password") {}
            TapSettingsRow(icon: "bell.fill", color: .red, label: "Notification Preferences") {}
            TapSettingsRow(icon: "arrow.down.circle.fill", color: .blue, label: "Export My Data") {}
            TapSettingsRow(icon: "trash.fill", color: .red, label: "Delete Account") {}
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        auth.session?.user.email?
            .components(separatedBy: "@").first?
            .capitalized ?? "User"
    }
    private var initial: String { String(displayName.prefix(1)) }
    private var shortId: String {
        auth.session?.user.id.uuidString
            .components(separatedBy: "-").first ?? "—"
    }
    private var memberSince: String {
        guard let user = auth.session?.user else { return "—" }
        let out = DateFormatter()
        out.dateFormat = "MMMM yyyy"
        return out.string(from: user.createdAt)
    }
}

private struct ProfileInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
