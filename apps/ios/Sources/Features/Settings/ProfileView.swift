import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var profileService: ProfileService
    @State private var showEdit = false
    @State private var showPasswordAlert = false
    @State private var passwordAlertMsg = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                avatarSection
                infoCard
                accountSection
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showEdit = true }
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .sheet(isPresented: $showEdit) {
            EditProfileView()
                .environmentObject(profileService)
        }
        .alert("Password Reset", isPresented: $showPasswordAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(passwordAlertMsg)
        }
        .confirmationDialog("Delete Account", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                Task { try? await auth.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All your data will be deleted.")
        }
        .task {
            if profileService.profile == nil, let uid = auth.session?.user.id {
                await profileService.load(userId: uid)
            }
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
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
                Text(preferredInitial)
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .blue.opacity(0.4), radius: 16, y: 6)

            Text(preferredName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text(auth.session?.user.email ?? "")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        GlassCard {
            VStack(spacing: 0) {
                InfoRow(label: "Email", value: auth.session?.user.email ?? "—")
                rowDivider
                InfoRow(label: "Display Name", value: profileService.profile?.preferredName ?? "—")
                rowDivider
                InfoRow(label: "Account ID", value: shortId)
                rowDivider
                InfoRow(label: "Member since", value: memberSince)
                if let phone = profileService.profile?.phone, !phone.isEmpty {
                    rowDivider
                    InfoRow(label: "Phone", value: phone)
                }
            }
        }
    }

    // MARK: - Account actions

    private var accountSection: some View {
        SettingsGroup(title: "Account") {
            TapSettingsRow(icon: "key.fill", color: .orange, label: "Change Password") {
                sendPasswordReset()
            }
            TapSettingsRow(icon: "bell.fill", color: .red, label: "Notification Preferences") {}
            TapSettingsRow(icon: "arrow.down.circle.fill", color: .blue, label: "Export My Data") {}
            TapSettingsRow(icon: "trash.fill", color: .red, label: "Delete Account") {
                showDeleteConfirm = true
            }
        }
    }

    // MARK: - Helpers

    private func sendPasswordReset() {
        Task {
            do {
                try await profileService.sendPasswordReset()
                passwordAlertMsg = "A password reset link was sent to \(auth.session?.user.email ?? "your email")."
            } catch {
                passwordAlertMsg = error.localizedDescription
            }
            showPasswordAlert = true
        }
    }

    private var preferredName: String {
        profileService.profile?.preferredName ?? fallbackName
    }
    private var preferredInitial: String {
        profileService.profile?.initial ?? String(fallbackName.prefix(1)).uppercased()
    }
    private var fallbackName: String {
        auth.session?.user.email?.components(separatedBy: "@").first?.capitalized ?? "User"
    }
    private var shortId: String {
        auth.session?.user.id.uuidString.components(separatedBy: "-").first ?? "—"
    }
    private var memberSince: String {
        guard let user = auth.session?.user else { return "—" }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: user.createdAt)
    }
    private var rowDivider: some View {
        Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 16)
    }
}

private struct InfoRow: View {
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
