import SwiftUI

// MARK: - GuestModeView

struct GuestModeView: View {
    @EnvironmentObject private var propertyService: PropertyService

    @AppStorage("prvio.guest.wifi_name") private var wifiName = ""
    @AppStorage("prvio.guest.wifi_pass") private var wifiPass = ""
    @AppStorage("prvio.guest.rules") private var houseRules = ""
    @AppStorage("prvio.guest.notes") private var guestNotes = ""

    @State private var showShare = false
    @State private var shareItems: [Any] = []

    private var propertyName: String {
        propertyService.primary?.name ?? "My Home"
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerCard
                    wifiSection
                    rulesSection
                    notesSection
                    shareButtonCard
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Guest Mode")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareGuestInfo()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: shareItems)
                .ignoresSafeArea()
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "house.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(propertyName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    if let address = propertyService.primary?.addressLine1, !address.isEmpty {
                        Text(address)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .lineLimit(2)
                    }
                    Text("Guest information sheet")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()
            }
        }
    }

    // MARK: - WiFi Section

    private var wifiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "wifi", title: "WiFi")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    editableRow(icon: "wifi", placeholder: "Network name", text: $wifiName)
                    rowDivider
                    editableRow(icon: "lock.fill", placeholder: "Password", text: $wifiPass, isSecure: false)
                }
            }
        }
    }

    // MARK: - Rules Section

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "list.bullet.clipboard.fill", title: "House Rules")
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.clipboard.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        Text("Rules")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                    TextField(
                        "e.g. No smoking indoors, quiet hours after 10pm, please recycle…",
                        text: $houseRules,
                        axis: .vertical
                    )
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .lineLimit(4...12)
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "note.text", title: "Important Notes")
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        Text("Notes")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.5))
                    }
                    TextField(
                        "e.g. Trash pickup is Monday, parking spot #4, call me if anything…",
                        text: $guestNotes,
                        axis: .vertical
                    )
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .lineLimit(4...10)
                }
            }
        }
    }

    // MARK: - Share Button

    private var shareButtonCard: some View {
        Button {
            shareGuestInfo()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                Text("Share Guest Info")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
        }
        .padding(.leading, 6)
    }

    private func editableRow(icon: String, placeholder: String, text: Binding<String>, isSecure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func shareGuestInfo() {
        var text = "Welcome to \(propertyName)!\n\n"

        text += "📶 WiFi\n"
        if !wifiName.isEmpty { text += "Network: \(wifiName)\n" }
        if !wifiPass.isEmpty { text += "Password: \(wifiPass)\n" }
        text += "\n"

        if !houseRules.isEmpty {
            text += "🏠 House Rules\n\(houseRules)\n\n"
        }

        if !guestNotes.isEmpty {
            text += "📝 Notes\n\(guestNotes)\n"
        }

        shareItems = [text]
        showShare = true
        HapticFeedback.impact(.medium)
    }
}
