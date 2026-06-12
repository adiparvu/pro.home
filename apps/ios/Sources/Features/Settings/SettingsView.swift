import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @State private var showSignOutConfirm = false

    var userEmail: String {
        auth.session?.user.email ?? "—"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    PageHeader(title: "Settings")
                        .padding(.bottom, 4)

                    // Profile card
                    GlassCard {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(.white.opacity(0.1))
                                    .frame(width: 52, height: 52)
                                Text(userEmail.prefix(1).uppercased())
                                    .font(.title3.weight(.bold))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Property Owner")
                                    .font(.subheadline.weight(.semibold))
                                Text(userEmail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 20)

                    // Sections
                    SettingsSection(title: "Property") {
                        SettingsRow(icon: "house", label: "My Property")
                        SettingsRow(icon: "doc.text", label: "Documents")
                        SettingsRow(icon: "person.2", label: "Tenants")
                    }

                    SettingsSection(title: "Notifications") {
                        SettingsToggleRow(icon: "bell", label: "Push Notifications", isOn: .constant(true))
                        SettingsToggleRow(icon: "envelope", label: "Email Alerts", isOn: .constant(true))
                        SettingsToggleRow(icon: "exclamationmark.circle", label: "Overdue Reminders", isOn: .constant(true))
                    }

                    SettingsSection(title: "App") {
                        SettingsRow(icon: "paintbrush", label: "Appearance")
                        SettingsRow(icon: "lock.shield", label: "Security")
                        SettingsRow(icon: "link", label: "Integrations")
                    }

                    SettingsSection(title: "Support") {
                        SettingsRow(icon: "questionmark.circle", label: "Help & FAQ")
                        SettingsRow(icon: "star", label: "Rate App")
                        SettingsRow(icon: "info.circle", label: "About · v1.0.0")
                    }

                    // Sign out
                    Button {
                        showSignOutConfirm = true
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(.red.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(.red.opacity(0.15), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)

                    Spacer(minLength: 100)
                }
            }
        }
        .confirmationDialog("Sign out?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await auth.signOut() }
            }
        } message: {
            Text("You'll need to sign back in to access your property.")
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1)
                .padding(.horizontal, 24)

            VStack(spacing: 0) {
                content()
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 20)
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let label: String

    var body: some View {
        Button {} label: {
            HStack(spacing: 12) {
                IconBadge(icon: icon, size: 32)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        Divider().overlay(.white.opacity(0.06)).padding(.leading, 60)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(icon: icon, size: 32)
            Text(label)
                .font(.body)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        Divider().overlay(.white.opacity(0.06)).padding(.leading, 60)
    }
}
