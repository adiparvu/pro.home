import SwiftUI
import AppIntents

struct SiriShortcutsView: View {
    @State private var donated = false
    @State private var showActivatedBanner = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                PageHeader(titleKey: "Siri & Shortcuts", subtitleKey: "PRVIO")

                headerCard

                if showActivatedBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.15, green: 0.80, blue: 0.40))
                        Text("All \(PRVIOShortcutsProvider.appShortcuts.count) shortcuts activated for Siri!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.15, green: 0.80, blue: 0.40).opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                shortcutsSection
                donateSection

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

    private let shortcuts: [(icon: String, color: Color, title: String, phrases: [String])] = [
        ("house.fill",    .blue,
         "Open PRVIO",    ["\"Open PRVIO\"", "\"Show PRVIO dashboard\""]),
        ("checklist",     Color(red: 0.3, green: 0.85, blue: 0.45),
         "New Task",      ["\"Add task in PRVIO\"", "\"New task in PRVIO\""]),
        ("drop.fill",     Color(red: 0.15, green: 0.65, blue: 1.0),
         "Water Plant",   ["\"Water plant in PRVIO\"", "\"Mark plant watered in PRVIO\""]),
        ("leaf.fill",     Color(red: 0.15, green: 0.72, blue: 0.37),
         "Open Plants",   ["\"Open plants in PRVIO\"", "\"Show plants in PRVIO\""]),
        ("cart.fill",     Color(red: 0.35, green: 0.65, blue: 1.0),
         "Shopping List", ["\"Open shopping in PRVIO\"", "\"Shopping list PRVIO\""]),
        ("message.fill",  Color(red: 0.2, green: 0.55, blue: 0.95),
         "Family Chat",   ["\"Open family chat in PRVIO\"", "\"Family chat PRVIO\""]),
        ("sparkles",      Color(red: 0.55, green: 0.35, blue: 0.95),
         "Ask ARIA",      ["\"Ask ARIA in PRVIO\"", "\"Talk to PRVIO\""]),
    ]

    private var shortcutsSection: some View {
        VStack(spacing: 0) {
            sectionHeader("AVAILABLE COMMANDS")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { idx, s in
                        shortcutRow(icon: s.icon, color: s.color, title: LocalizedStringKey(s.title), phrases: s.phrases)
                        if idx < shortcuts.count - 1 { rowDivider }
                    }
                }
            }
        }
    }

    private func shortcutRow(icon: String, color: Color, title: LocalizedStringKey, phrases: [String]) -> some View {
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
                        Text(LocalizedStringKey(phrase))
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

    // MARK: Donate + Shortcuts app link

    private var donateSection: some View {
        VStack(spacing: 12) {
            Button {
                guard !donated else { return }
                Task {
                    await PRVIOShortcutsProvider.updateAppShortcutParameters()
                    HapticFeedback.success()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        donated = true
                        showActivatedBanner = true
                    }
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { donated = false; showActivatedBanner = false }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: donated ? "checkmark.circle.fill" : "wand.and.stars")
                        .font(.system(size: 16, weight: .semibold))
                    Text(LocalizedStringKey(donated ? "Commands Activated!" : "Activate Siri Commands"))
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
                            startPoint: .leading, endPoint: .trailing)),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: donated)

            ShortcutsLink {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 15, weight: .semibold))
                    Text("View in Shortcuts App")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(red: 0.55, green: 0.35, blue: 0.95).opacity(0.25), lineWidth: 1))
            }

            Text("Activate once — Siri learns all \(shortcuts.count) commands. To remove, go to iPhone Settings › Siri.")
                .font(.system(size: 11))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ text: LocalizedStringKey) -> some View {
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
