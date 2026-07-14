import SwiftUI

// MARK: - Weather Engine · audition gallery (dev/showcase surface)
//
// A full-screen `WeatherStageView` with an overlaid picker for all 19
// conditions. Tapping a condition calls `engine.transition(to:)` LIVE, so the
// cross-dissolve is exactly what an on-device auditor sees — this is the phase's
// device test bed. It is reached from Settings → Appearance with an honest
// "beta" label; it drives the engine's manual override and nothing else (the
// auto weather path stays unwired this phase — see WeatherStageView's note).
struct WeatherGalleryView: View {
    private var engine = WeatherEngine.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: AppSpacing.sm)]

    var body: some View {
        ZStack(alignment: .bottom) {
            // The live stage fills the screen behind the controls.
            WeatherStageView()
                .ignoresSafeArea()

            controls
        }
        .navigationTitle("weather_gallery_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: Controls

    private var controls: some View {
        // PROOF-OF-CONCEPT (Phase 2): wrap the gallery controls in a
        // `WeatherFlashProvider` so the current-condition card can brighten in
        // sync with the thunderstorm's lightning. This is the ONLY app surface
        // wired to the flash hook this phase; app-wide integration (wrapping a
        // high-level container, adding `.weatherFlashResponsive()` to Liquid
        // Glass cards) is deferred — see WeatherFlashEnvironment.swift.
        WeatherFlashProvider {
            VStack(spacing: AppSpacing.md) {
                currentCard
                    .weatherFlashResponsive()

                conditionScroll
            }
            .padding(AppSpacing.base)
        }
    }

    private var conditionScroll: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
                ForEach(WeatherCondition.allCases) { condition in
                    conditionChip(condition)
                }
            }
            .padding(AppSpacing.base)
        }
        .frame(maxHeight: 280)
        .liquidGlass(cornerRadius: AppRadius.sheet)
    }

    /// The current condition, its renderer tier, and a flagship badge — so an
    /// auditor always knows what they are looking at.
    private var currentCard: some View {
        let current = engine.current
        return HStack(spacing: AppSpacing.md) {
            Image(systemName: current.symbolName)
                .font(AppFont.title2)
                .foregroundStyle(.white)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(current.displayNameKey)
                    .font(AppFont.headline)
                    .foregroundStyle(.white)
                HStack(spacing: AppSpacing.xs) {
                    Text(current.tier.rawValue)
                        .font(AppFont.caption2)
                        .foregroundStyle(.white.opacity(AppOpacity.emphasis))
                    if current.isFlagship {
                        Text("weather_gallery_flagship")
                            .font(AppFont.label)
                            .foregroundStyle(.black)
                            .padding(.horizontal, AppSpacing.xs)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.85)))
                    }
                }
            }
            Spacer()
        }
        .padding(AppSpacing.base)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private func conditionChip(_ condition: WeatherCondition) -> some View {
        let isSelected = engine.current == condition
        return Button {
            engine.transition(to: condition, reduceMotion: reduceMotion)
            HapticFeedback.selection()
        } label: {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: condition.symbolName)
                    .font(AppFont.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
                    .frame(height: 26)
                Text(condition.displayNameKey)
                    .font(AppFont.caption2)
                    .foregroundStyle(.white.opacity(AppOpacity.emphasis))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.24 : 0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .strokeBorder(.white.opacity(isSelected ? 0.7 : 0), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
