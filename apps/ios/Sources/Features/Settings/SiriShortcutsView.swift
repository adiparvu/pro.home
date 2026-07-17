import SwiftUI
import AppIntents

// MARK: - Siri & Shortcuts
//
// The voice manual. One source of truth (`entries`) mirrors every shortcut
// registered in PRVIOShortcutsProvider — all ten, grouped the way you think
// (navigate / act / ask) — and the example phrases shown are the REAL ones
// Siri accepts, localized exactly like AppShortcuts.xcstrings, so what you
// read is what you can say.

struct SiriShortcutsView: View {
    @State private var donated = false
    @State private var showActivatedBanner = false

    private static let shortcutCount = PRVIOShortcutsProvider.appShortcuts.count

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {

                headerCard

                if showActivatedBanner {
                    activatedBanner
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ForEach(SiriCommandGroup.all) { group in
                    section(group)
                }

                donateSection

                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Header

    private var headerCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                // Siri's colour lives on the glyph — the surface stays glass.
                Image(systemName: "waveform")
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [Color.brandSkyBlue, Color.brandPurple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 48, height: 48)
                    .mediaGlass(in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Siri Commands")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.primary)
                    Text("Control PRVIO with your voice")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    private var activatedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.brandSuccess)
            Text(String(format: String(localized: "siri_activated_banner"), Self.shortcutCount))
                .font(AppFont.footnote)
                .foregroundStyle(.primary)
        }
        .padding(AppSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mediaGlass(in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }

    // MARK: Command groups

    private func section(_ group: SiriCommandGroup) -> some View {
        VStack(spacing: 0) {
            Text(group.title)
                .font(AppFont.label)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, AppSpacing.sm)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(group.commands.enumerated()), id: \.element.id) { idx, cmd in
                        row(cmd)
                        if idx < group.commands.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private func row(_ cmd: SiriCommand) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image(systemName: cmd.icon)
                    .font(AppFont.footnote)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(cmd.tint)
                    .frame(width: 34, height: 34)
                    .mediaGlass(in: Circle())

                Text(cmd.title)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "mic.fill")
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(cmd.phrases, id: \.self) { phrase in
                    HStack(spacing: 6) {
                        Image(systemName: "quote.opening")
                            .font(AppFont.scaled(9))
                            .foregroundStyle(Color.primary.opacity(0.3))
                        Text(LocalizedStringKey(phrase))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(0.55))
                            .italic()
                    }
                }
            }
            .padding(.leading, 46)
        }
        .padding(AppSpacing.base)
        .accessibilityElement(children: .combine)
    }

    // MARK: Activate + Shortcuts app link

    private var donateSection: some View {
        VStack(spacing: 12) {
            GlassWideButton(icon: donated ? "checkmark.circle.fill" : "wand.and.stars",
                            label: donated ? "siri_activated" : "Activate Siri Commands") {
                guard !donated else { return }
                Task {
                    PRVIOShortcutsProvider.updateAppShortcutParameters()
                    HapticFeedback.success()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        donated = true
                        showActivatedBanner = true
                    }
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(AppMotion.state) { donated = false; showActivatedBanner = false }
                }
            }

            ShortcutsLink {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(AppFont.subheadline)
                    Text("View in Shortcuts App")
                        .font(AppFont.subheadline)
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .mediaGlass(in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            Text(String(format: String(localized: "siri_footer"), Self.shortcutCount))
                .font(AppFont.scaled(11))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.sm)
        }
    }
}

// MARK: - Command catalogue (mirrors PRVIOShortcutsProvider, grouped)

private struct SiriCommand: Identifiable {
    let id: String
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    /// The REAL spoken phrases (same wording AppShortcuts.xcstrings registers).
    /// Kept as key strings — LocalizedStringKey isn't Hashable, so ForEach
    /// needs a Hashable identity; Text re-wraps them at render time.
    let phrases: [String]
}

private struct SiriCommandGroup: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let commands: [SiriCommand]

    static let all: [SiriCommandGroup] = [
        SiriCommandGroup(id: "nav", title: "siri_sec_nav", commands: [
            SiriCommand(id: "open", icon: "house.fill", tint: .blue,
                        title: "Open PRVIO",
                        phrases: ["siri_ph_open_1", "siri_ph_open_2"]),
            SiriCommand(id: "plants", icon: "leaf.fill", tint: Color.brandSuccess,
                        title: "Open Plants",
                        phrases: ["siri_ph_plants_1", "siri_ph_plants_2"]),
            SiriCommand(id: "shopping", icon: "cart.fill", tint: .orange,
                        title: "Shopping List",
                        phrases: ["siri_ph_shopping_1", "siri_ph_shopping_2"]),
            SiriCommand(id: "chat", icon: "message.fill", tint: Color.brandPrimaryBlue,
                        title: "Chat",
                        phrases: ["siri_ph_chat_1", "siri_ph_chat_2"]),
        ]),
        SiriCommandGroup(id: "act", title: "siri_sec_actions", commands: [
            SiriCommand(id: "newtask", icon: "checklist", tint: .blue,
                        title: "New Task",
                        phrases: ["siri_ph_newtask_1", "siri_ph_newtask_2"]),
            SiriCommand(id: "complete", icon: "checkmark.circle.fill", tint: Color.brandSuccess,
                        title: "siri_complete_task",
                        phrases: ["siri_ph_complete_1", "siri_ph_complete_2"]),
            SiriCommand(id: "water", icon: "drop.fill", tint: Color.brandSkyBlue,
                        title: "siri_water_plant",
                        phrases: ["siri_ph_water_1", "siri_ph_water_2"]),
            SiriCommand(id: "checkoff", icon: "cart.badge.minus", tint: .orange,
                        title: "siri_check_item",
                        phrases: ["siri_ph_check_1", "siri_ph_check_2"]),
            SiriCommand(id: "quick", icon: "bolt.fill", tint: Color.brandWarning,
                        title: "siri_quick_action",
                        phrases: ["siri_ph_quick_1", "siri_ph_quick_2"]),
        ]),
        SiriCommandGroup(id: "aria", title: "siri_sec_assistant", commands: [
            SiriCommand(id: "aria", icon: "sparkles", tint: Color.brandPurple,
                        title: "Ask ARIA",
                        phrases: ["siri_ph_aria_1", "siri_ph_aria_2"]),
        ]),
    ]
}
