import SwiftUI
import AppIntents

struct SiriShortcutsView: View {
    @State private var donated = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                PageHeader(title: "Siri & Shortcuts", subtitle: "PRVIO")

                headerCard
                shortcutsSection
                donateButton

                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private var headerCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(red: 0.55, green: 0.35, blue: 0.95), Color(red: 0.4, green: 0.25, blue: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 48, height: 48)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Siri Commands")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Control PRVIO with your voice")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    // MARK: Shortcuts list

    private var shortcutsSection: some View {
        VStack(spacing: 0) {
            sectionHeader("AVAILABLE COMMANDS")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    shortcutRow(
                        icon: "checklist",
                        color: Color(red: 0.3, green: 0.85, blue: 0.45),
                        title: "New Task",
                        phrases: [
                            "\"Add task in PRVIO\"",
                            "\"New task in PRVIO\""
                        ]
                    )
                    rowDivider
                    shortcutRow(
                        icon: "drop.fill",
                        color: .blue,
                        title: "Water plant",
                        phrases: [
                            "\"Water plant in PRVIO\"",
                            "\"Mark watered in PRVIO\""
                        ]
                    )
                    rowDivider
                    shortcutRow(
                        icon: "cart.fill",
                        color: Color(red: 0.35, green: 0.65, blue: 1.0),
                        title: "Open shopping",
                        phrases: [
                            "\"Open shopping in PRVIO\"",
                            "\"Shopping list PRVIO\""
                        ]
                    )
                    rowDivider
                    shortcutRow(
                        icon: "message.fill",
                        color: Color(red: 0.35, green: 0.65, blue: 1.0),
                        title: "Family chat",
                        phrases: [
                            "\"Open chat in PRVIO\"",
                            "\"Family chat PRVIO\""
                        ]
                    )
                }
            }
        }
    }

    private func shortcutRow(icon: String, color: Color, title: String, phrases: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "mic.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.primary.opacity(0.25))
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(phrases, id: \.self) { phrase in
                    HStack(spacing: 6) {
                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.primary.opacity(0.3))
                        Text(phrase)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .italic()
                    }
                }
            }
            .padding(.leading, 44)
        }
        .padding(14)
    }

    // MARK: Donate button

    private var donateButton: some View {
        VStack(spacing: 10) {
            Button {
                guard !donated else { return }
                Task {
                    await PRVIOShortcutsProvider.updateAppShortcutParameters()
                    HapticFeedback.success()
                    withAnimation { donated = true }
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { donated = false }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: donated ? "checkmark.circle.fill" : "wand.and.stars")
                        .font(.system(size: 16, weight: .semibold))
                    Text(donated ? "Commands activated!" : "Activate Siri Commands")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    donated
                        ? AnyShapeStyle(Color(red: 0.15, green: 0.80, blue: 0.40))
                        : AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.55, green: 0.35, blue: 0.95), Color(red: 0.4, green: 0.25, blue: 0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: donated)

            Text("To disable Siri commands, go to iPhone Settings › Siri › App Shortcuts.")
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.horizontal, 14)
    }
}
