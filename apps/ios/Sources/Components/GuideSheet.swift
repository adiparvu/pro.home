import SwiftUI

// MARK: - Guide sheet ("how does this work?")
//
// The reusable answer to every info button in the app: a friendly, deeply
// detailed walkthrough of one surface — what the thing IS (in words a child
// can follow), numbered steps for how to use it, concrete examples, and the
// honest limits. Content is data (GuideTopic), so every new surface only
// declares its sections instead of building another bespoke sheet.

struct GuideTopic {
    let icon: String
    let title: LocalizedStringKey
    let intro: LocalizedStringKey
    let sections: [GuideSection]
    var accent: Color = .accentColor
}

struct GuideSection: Identifiable {
    let id = UUID()
    let icon: String
    let title: LocalizedStringKey
    /// Free paragraph under the section title (what/why).
    var body: LocalizedStringKey? = nil
    /// Numbered how-to steps, rendered 1-2-3 with circles.
    var steps: [LocalizedStringKey] = []
    /// "For example:" bullets — concrete, real-life examples.
    var examples: [LocalizedStringKey] = []
    /// An honest limitation or requirement, shown with a small warning tint.
    var note: LocalizedStringKey? = nil
}

struct GuideSheet: View {
    let topic: GuideTopic
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    header
                    ForEach(topic.sections) { section in
                        sectionCard(section)
                    }
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFont.scaled(22))
                            .foregroundStyle(Color.primary.opacity(0.3))
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Image(systemName: topic.icon)
                .font(AppFont.scaled(26, weight: .semibold))
                .foregroundStyle(topic.accent)
                .frame(width: 56, height: 56)
                .glassRoundedRect(AppRadius.lg)
            Text(topic.title)
                .font(AppFont.scaled(26, weight: .bold))
                .foregroundStyle(.primary)
            Text(topic.intro)
                .font(AppFont.scaled(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func sectionCard(_ section: GuideSection) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(AppFont.scaled(16, weight: .semibold))
                    .foregroundStyle(topic.accent)
                    .frame(width: 24)
                Text(section.title)
                    .font(AppFont.scaled(17, weight: .semibold))
                    .foregroundStyle(Color.glassInk)
            }

            if let body = section.body {
                Text(body)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(Color.primary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !section.steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(section.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(AppFont.scaled(13, weight: .bold))
                                .foregroundStyle(topic.accent)
                                .frame(width: 24, height: 24)
                                .background(topic.accent.opacity(AppOpacity.tintedFill), in: Circle())
                            Text(step)
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if !section.examples.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("guide_examples")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.secondary)
                    ForEach(Array(section.examples.enumerated()), id: \.offset) { _, example in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill")
                                .font(AppFont.scaled(11))
                                .foregroundStyle(Color.brandWarning)
                                .padding(.top, 3)
                            Text(example)
                                .font(AppFont.scaled(14))
                                .foregroundStyle(Color.primary.opacity(0.75))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(AppSpacing.md)
                .background(Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            if let note = section.note {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.brandWarning)
                        .padding(.top, 2)
                    Text(note)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
    }
}

// MARK: - Reusable toolbar info button

struct GuideInfoButton: View {
    let topic: GuideTopic
    @State private var showGuide = false

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            showGuide = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(AppFont.scaled(17, weight: .medium))
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(Text("guide_info_a11y"))
        .sheet(isPresented: $showGuide) { GuideSheet(topic: topic) }
    }
}
