import SwiftUI

/// Settings → Floating Buttons.
///
/// Rebuilt to the Settings → Notifications idiom: a live miniature of the
/// speed dial up top, one master switch that gates everything, and a single
/// compact card with one row per page. Each row opens a detail screen where
/// that page's actions are enabled individually — the dial supports multiple
/// actions on every page, so every row navigates.
struct QuickActionsSettingsView: View {
    @Environment(AppSettings.self) private var appSettings
    @State private var showResetDialog = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                FabDialPreview(host: previewHost)

                masterCard

                if appSettings.fabMasterEnabled {
                    pagesSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                resetFooter

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
            .animation(.smooth(duration: 0.28), value: appSettings.fabMasterEnabled)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Floating Buttons")
        .navigationBarTitleDisplayMode(.large)
    }

    /// The page the miniature demonstrates: the first one that would really
    /// show a dial right now, falling back to Home.
    private var previewHost: FloatingButtonHost {
        FloatingButtonHost.allCases.first {
            appSettings.fabPageVisible($0) && !appSettings.fabActions($0).isEmpty
        } ?? .home
    }

    // MARK: - Master switch

    private var masterCard: some View {
        HStack(spacing: 12) {
            SettingsMonoBadge(icon: "plus")
            VStack(alignment: .leading, spacing: 2) {
                Text("Floating button")
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                Text("Shows quick actions on top of your pages.")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { appSettings.fabMasterEnabled },
                set: { newValue in
                    HapticFeedback.selection()
                    appSettings.setFabMasterEnabled(newValue)
                }
            ))
            .labelsHidden()
            .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    // MARK: - Pages

    private var pagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("On which pages it appears")
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)

            VStack(spacing: 0) {
                ForEach(FloatingButtonHost.allCases) { host in
                    FabPageRow(host: host, isLast: host == FloatingButtonHost.allCases.last)
                }
            }
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }

    // MARK: - Reset

    private var resetFooter: some View {
        Button {
            HapticFeedback.impact(.light)
            showResetDialog = true
        } label: {
            Text("Reset to defaults")
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .glassRoundedRect(AppRadius.lg)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Restore the default buttons on every page?",
                            isPresented: $showResetDialog,
                            titleVisibility: .visible) {
            Button("Reset to defaults", role: .destructive) {
                appSettings.resetFabConfiguration()
                HapticFeedback.success()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Live dial preview

/// A non-interactive miniature of the actual speed dial, built from the same
/// visual vocabulary as `FloatingSpeedDial` (glass capsule labels + glass
/// circles), reflecting the currently enabled actions for `host` live.
private struct FabDialPreview: View {
    @Environment(AppSettings.self) private var appSettings
    let host: FloatingButtonHost

    private var actions: [DashboardQuickAction] { appSettings.fabActions(host) }
    private var isMenu: Bool { actions.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Text("Preview")
                    .textCase(.uppercase)
                Text("·")
                Text(host.title)
                    .textCase(.uppercase)
            }
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .padding([.top, .leading], AppSpacing.base)

            dial
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, AppSpacing.lg)
                .padding(.vertical, AppSpacing.lg)
                .opacity(appSettings.fabMasterEnabled && appSettings.fabPageVisible(host) ? 1 : 0.35)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
            .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preview"))
        .animation(.smooth(duration: 0.25), value: actions)
    }

    @ViewBuilder
    private var dial: some View {
        if actions.isEmpty {
            Text("No active actions")
                .font(AppFont.footnote)
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            VStack(alignment: .trailing, spacing: 9) {
                if isMenu {
                    ForEach(actions) { action in
                        HStack(spacing: 8) {
                            Text(action.title)
                                .font(AppFont.caption2)
                                .foregroundStyle(.primary)
                                .padding(.horizontal, AppSpacing.md)
                                .padding(.vertical, 5)
                                .glassCapsule()
                            Image(systemName: action.icon)
                                .font(AppFont.caption)
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .glassCircle()
                        }
                    }
                }
                // The main button — a plus for a menu, the action's own icon
                // when the page has a single action (like the real dial).
                Image(systemName: isMenu ? "plus" : (actions.first?.icon ?? "plus"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .glassCircle()
                    .shadow(color: Color.primary.opacity(0.18), radius: 10, y: 3)
            }
        }
    }
}

// MARK: - Page row

private struct FabPageRow: View {
    @Environment(AppSettings.self) private var appSettings
    let host: FloatingButtonHost
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                FabPageDetailView(host: host)
            } label: {
                HStack(spacing: 12) {
                    SettingsMonoBadge(icon: host.icon)
                    Text(host.title)
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appSettings.fabPageVisible(host) },
                        set: { newValue in
                            HapticFeedback.selection()
                            appSettings.setFabVisible(host, newValue)
                        }
                    ))
                    .labelsHidden()
                    .tint(.accentColor)
                    .scaleEffect(0.82, anchor: .trailing)
                    Image(systemName: "chevron.right")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(host.title))

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(AppOpacity.hairline))
                    .frame(height: 0.4)
                    .padding(.leading, 58)
            }
        }
    }
}

// MARK: - Page detail (per-page actions)

/// One page's speed dial: its own live miniature, the visibility toggle,
/// and the list of actions that can appear on it.
private struct FabPageDetailView: View {
    @Environment(AppSettings.self) private var appSettings
    let host: FloatingButtonHost

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                FabDialPreview(host: host)

                visibilityCard

                if appSettings.fabPageVisible(host) {
                    actionsSection
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Text("If a page has a single active action, the button triggers it directly. With multiple actions, the button opens a menu.")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppSpacing.sm)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
            .animation(.smooth(duration: 0.28), value: appSettings.fabPageVisible(host))
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(host.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var visibilityCard: some View {
        HStack(spacing: 12) {
            SettingsMonoBadge(icon: appSettings.fabPageVisible(host) ? "eye.fill" : "eye.slash.fill")
            Text("Show button")
                .font(AppFont.body)
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { appSettings.fabPageVisible(host) },
                set: { newValue in
                    HapticFeedback.selection()
                    appSettings.setFabVisible(host, newValue)
                }
            ))
            .labelsHidden()
            .tint(.accentColor)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions on this page")
                .textCase(.uppercase)
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.sm)

            VStack(spacing: 0) {
                ForEach(DashboardQuickAction.allCases) { action in
                    QuickActionToggleRow(
                        action: action,
                        isOn: Binding(
                            get: { appSettings.isFabActionEnabled(host, action) },
                            set: { newValue in
                                HapticFeedback.selection()
                                appSettings.setFabAction(host, action, enabled: newValue)
                            }
                        ),
                        isLast: action == DashboardQuickAction.allCases.last
                    )
                }
            }
            .liquidGlass(cornerRadius: AppRadius.xl)
        }
    }
}

// MARK: - Shared bits

/// Monochrome SF icon on a subtle neutral square — the row badge for this
/// settings page family.
private struct SettingsMonoBadge: View {
    let icon: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.primary)
        }
    }
}

/// A single quick action with its enable toggle. Color survives here — the
/// page that configures an action is the one place its tint is shown.
private struct QuickActionToggleRow: View {
    let action: DashboardQuickAction
    @Binding var isOn: Bool
    var isLast: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(action.color.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: action.icon)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(action.color)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                    Text(action.subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(.accentColor)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 11)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(AppOpacity.hairline))
                    .frame(height: 0.4)
                    .padding(.leading, 58)
            }
        }
    }
}
