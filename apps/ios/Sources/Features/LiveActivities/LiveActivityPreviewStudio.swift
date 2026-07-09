import SwiftUI

// MARK: - Live Activity Preview Studio
//
// A premium, per-surface preview of every Live Activity kind: Lock Screen,
// the three Dynamic Island densities, StandBy, the watch Smart Stack and a
// Home Screen widget frame. Reuses the SAME mocks the settings screen uses
// (KindLockScreenMock / DynamicIslandMock) and feeds them the kind's
// EFFECTIVE appearance preferences, so what the studio shows is what the
// real activity will render — never a fantasy configuration. There is no
// CarPlay surface on purpose: Live Activities do not exist on CarPlay.

struct LiveActivityPreviewStudio: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var kind: LiveActivityKind = .delivery
    @State private var surface: Surface = .lockScreen

    // MARK: Surfaces

    private enum Surface: String, CaseIterable, Identifiable {
        case lockScreen, islandExpanded, islandCompact, islandMinimal
        case standBy, watch, widget

        var id: String { rawValue }

        /// Localized display name — used by the chips and the caption.
        var name: String {
            switch self {
            case .lockScreen:     return String(localized: "la_surface_lock")
            case .islandExpanded: return String(localized: "la_surface_island_expanded")
            case .islandCompact:  return String(localized: "la_surface_island_compact")
            case .islandMinimal:  return String(localized: "la_surface_island_minimal")
            case .standBy:        return String(localized: "la_surface_standby")
            case .watch:          return String(localized: "la_surface_watch")
            case .widget:         return String(localized: "la_surface_widget")
            }
        }

        var icon: String {
            switch self {
            case .lockScreen:     return "lock.fill"
            case .islandExpanded: return "capsule.fill"
            case .islandCompact:  return "capsule.lefthalf.filled"
            case .islandMinimal:  return "circle.fill"
            case .standBy:        return "clock.fill"
            case .watch:          return "applewatch"
            case .widget:         return "square.grid.2x2.fill"
            }
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: AppSpacing.lg) {
                kindChips
                surfaceChips
                previewCanvas
                captionBlock
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("la_studio_title")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Kind chips (same pattern as the settings screen's kindChip)

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(LiveActivityKind.allCases) { k in
                    kindChip(k)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func kindChip(_ k: LiveActivityKind) -> some View {
        let selected = kind == k
        return Button {
            HapticFeedback.selection()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { kind = k }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: k.icon)
                    .font(AppFont.subheadline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(k.color)
                    .frame(width: 40, height: 40)
                    .mediaGlass(in: Circle(), interactive: true)
                    .overlay(
                        Circle().strokeBorder(
                            selected ? Color.primary.opacity(0.35) : Color.clear,
                            lineWidth: 1.2)
                    )
                Text(k.title)
                    .font(AppFont.scaled(10, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : Color.secondaryTextColor)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 62)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(k.title))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Surface chips

    private var surfaceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.xs) {
                ForEach(Surface.allCases) { s in
                    GlassFilterChip(label: s.name, systemImage: s.icon,
                                    isSelected: surface == s) {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                            surface = s
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: Preview canvas

    private var previewCanvas: some View {
        ZStack {
            surfaceView
                .id(kind.rawValue + "·" + surface.rawValue)
                .transition(reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.94)))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 340)
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: kind)
        .animation(reduceMotion ? nil : .snappy(duration: 0.32), value: surface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(kind.title))
        .accessibilityValue(Text(verbatim: surface.name))
    }

    /// Every surface renders from the kind's EFFECTIVE appearance preferences
    /// (its own customization when enabled, the shared one otherwise) —
    /// exactly like the settings screen's preview card, so the studio never
    /// shows an appearance the real activity wouldn't have.
    @ViewBuilder
    private var surfaceView: some View {
        let raw = kind.rawValue
        let showProgress = LiveActivityPrefs.showProgress(for: raw)
        switch surface {
        case .lockScreen:
            KindLockScreenMock(kind: kind,
                               full: LiveActivityPrefs.showOnLockScreen(for: raw),
                               showProgress: showProgress,
                               showETA: LiveActivityPrefs.showETA(for: raw),
                               showProperty: LiveActivityPrefs.showProperty(for: raw))
        case .islandExpanded:
            DynamicIslandMock(kind: kind, style: .detailed, showProgress: showProgress)
        case .islandCompact:
            DynamicIslandMock(kind: kind, style: .compact, showProgress: showProgress)
        case .islandMinimal:
            DynamicIslandMock(kind: kind, style: .minimal, showProgress: showProgress)
        case .standBy:
            standByMock(showProgress: showProgress)
        case .watch:
            watchMock(showProgress: showProgress)
        case .widget:
            widgetMock(showProgress: showProgress)
        }
    }

    // MARK: StandBy mock — the dark, large-type nightstand canvas

    private func standByMock(showProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.base) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: kind.icon)
                    .font(AppFont.scaled(30, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(kind.color)
                Text(kind.previewHeadline)
                    .font(AppFont.scaled(21, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            Text(kind.previewStatus)
                .font(AppFont.scaled(44, weight: .bold, design: .rounded))
                .foregroundStyle(kind.color)
                .lineLimit(1).minimumScaleFactor(0.6)
            if showProgress {
                ProgressView(value: kind.previewProgress)
                    .tint(kind.color)
            }
        }
        .padding(AppSpacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: Watch mock — Smart Stack card in a watch-shaped frame

    private func watchMock(showProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: kind.icon)
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(kind.color)
                Text(verbatim: "PRVIO")
                    .font(AppFont.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            Text(kind.previewHeadline)
                .font(AppFont.footnoteEmphasis)
                .foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(kind.previewStatus)
                .font(AppFont.metric)
                .foregroundStyle(kind.color)
                .lineLimit(1)
            if showProgress {
                ProgressView(value: kind.previewProgress)
                    .tint(kind.color)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 180, height: 220, alignment: .leading)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 38, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: Widget mock — the Lock Screen card look in a Home Screen frame

    private func widgetMock(showProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Image(systemName: kind.icon)
                .font(AppFont.scaled(22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(kind.color)
            Spacer(minLength: 0)
            Text(kind.title)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(kind.previewStatus)
                .font(AppFont.metric)
                .foregroundStyle(kind.color)
                .lineLimit(1)
            if showProgress {
                ProgressView(value: kind.previewProgress)
                    .tint(kind.color)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 170, height: 170, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
    }

    // MARK: Caption — which surface, and the honest footnote

    private var captionBlock: some View {
        VStack(spacing: AppSpacing.xxs) {
            Text(verbatim: surface.name)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.secondaryTextColor)
            Text("la_studio_footnote")
                .font(AppFont.caption2)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
