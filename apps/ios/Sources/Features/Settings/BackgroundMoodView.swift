import SwiftUI

// MARK: - Background mood (Settings → Aspect → Fundal)
//
// The dedicated page for the living background: a hero preview that renders
// the ACTUAL backdrop of the selected mood with a real glass card on top
// (what you see is literally what every screen gets), an Auto row, and the
// three moods as tappable preview cards. Selection persists through
// `AppMoodEngine.override`.
//
// Honesty: the Auto explanation only claims sunrise/sunset when the engine
// actually has coordinates; otherwise it says it follows the clock.

struct BackgroundMoodView: View {
    private var engine: AppMoodEngine { .shared }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xxl) {
                heroPreview
                selectorSection
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text("mood_settings_title"))
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: Hero — the real backdrop, the real glass

    /// Live preview of the selected mood (Auto shows whatever it resolves to
    /// right now). The card inside is the app's actual `GlassCard`, and the
    /// preview adopts the mood's own color scheme, so glass, text, and
    /// ground are exactly what the rest of the app will render.
    private var heroPreview: some View {
        let mood = engine.resolved
        return ZStack {
            AppBackdrop(fixed: mood)
            GlassCard(padding: AppSpacing.lg, cornerRadius: AppRadius.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("mood_preview_card_title")
                        .font(AppFont.headline)
                        .foregroundStyle(.primary)
                    Text("mood_preview_card_body")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(AppSpacing.xxl)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        )
        // The app's scheme follows the mood; the preview must too, or the
        // glass would lie about its contrast.
        .environment(\.colorScheme, mood.palette.colorScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mood.titleKey))
    }

    // MARK: Selector — Auto + the three moods

    private var selectorSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            SettingsGroup(title: "mood_choose_title") {
                autoRow
            }
            HStack(spacing: AppSpacing.md) {
                ForEach(AppMood.allCases) { mood in
                    MoodPreviewCard(mood: mood,
                                    isSelected: engine.override == mood) {
                        select(mood)
                    }
                }
            }
        }
    }

    private var autoRow: some View {
        Button {
            select(nil)
        } label: {
            HStack(spacing: 12) {
                ColoredIconBadge(icon: "sparkles",
                                 color: engine.isAuto ? .accentColor : Color.primary.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text("mood_auto")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    // Only claim the sun when coordinates actually exist.
                    Text(engine.latitude != nil ? "mood_auto_explain_sun"
                                                : "mood_auto_explain_clock")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if engine.isAuto {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppFont.scaled(20))
                        .foregroundStyle(Color.accentColor)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(engine.isAuto ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ mood: AppMood?) {
        guard engine.override != mood else { return }
        HapticFeedback.selection()
        // The backdrop crossfades itself (.smooth 1.2 / instant under Reduce
        // Motion); this spring only carries the checkmarks and rings.
        withAnimation(.spring(response: 0.3)) { engine.override = mood }
    }
}

// MARK: - Mood preview card (mini gradient thumbnail + title)

private struct MoodPreviewCard: View {
    let mood: AppMood
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                AppBackdrop(fixed: mood)
                    .frame(height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.hairline,
                                          lineWidth: isSelected ? 2 : 1)
                    )
                Text(mood.titleKey)
                    .font(isSelected ? AppFont.footnoteEmphasis : AppFont.footnote)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary)
                                                : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(mood.titleKey))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
