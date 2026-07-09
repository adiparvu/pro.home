import SwiftUI

// MARK: - Help & FAQ (Apple Support-style)
//
// Not a flat list of eight questions: a searchable knowledge base grouped by
// theme, every answer written for the app as it actually is today. Content
// lives in the string catalog (RO+EN) keyed by entry id — adding a question
// is one array element plus two catalog strings.

private struct FAQEntry: Identifiable {
    let id: String   // key stem: "<id>_q" / "<id>_a" in the catalog

    var question: LocalizedStringKey { LocalizedStringKey(id + "_q") }
    var answer: LocalizedStringKey { LocalizedStringKey(id + "_a") }
    var questionText: String { String(localized: String.LocalizationValue(id + "_q")) }
    var answerText: String { String(localized: String.LocalizationValue(id + "_a")) }
}

private struct FAQSection: Identifiable {
    let id: String   // catalog key of the section title
    let icon: String
    let tint: Color
    let entries: [FAQEntry]

    var title: LocalizedStringKey { LocalizedStringKey(id) }
}

private enum FAQCatalog {
    static let sections: [FAQSection] = [
        FAQSection(id: "faq_cat_start", icon: "sparkles", tint: Color.brandPurple, entries: [
            FAQEntry(id: "faq_add_property"),
            FAQEntry(id: "faq_invite_family"),
            FAQEntry(id: "faq_switch_property"),
            FAQEntry(id: "faq_account_id"),
        ]),
        FAQSection(id: "faq_cat_home", icon: "checklist", tint: .blue, entries: [
            FAQEntry(id: "faq_recurring_tasks"),
            FAQEntry(id: "faq_health_score"),
            FAQEntry(id: "faq_calendar_sync"),
            FAQEntry(id: "faq_digital_twin"),
            FAQEntry(id: "faq_nfc_tags"),
        ]),
        FAQSection(id: "faq_cat_finance", icon: "creditcard.fill", tint: Color.brandSuccess, entries: [
            FAQEntry(id: "faq_currency"),
            FAQEntry(id: "faq_receipts"),
            FAQEntry(id: "faq_budgets"),
        ]),
        FAQSection(id: "faq_cat_chat", icon: "bubble.left.and.bubble.right.fill", tint: Color.brandSkyBlue, entries: [
            FAQEntry(id: "faq_communities"),
            FAQEntry(id: "faq_disappearing"),
            FAQEntry(id: "faq_statuses"),
            FAQEntry(id: "faq_roles"),
        ]),
        FAQSection(id: "faq_cat_aria", icon: "wand.and.stars", tint: .indigo, entries: [
            FAQEntry(id: "faq_aria"),
            FAQEntry(id: "faq_siri"),
            FAQEntry(id: "faq_widgets"),
            FAQEntry(id: "faq_watch"),
        ]),
        FAQSection(id: "faq_cat_data", icon: "lock.shield.fill", tint: .teal, entries: [
            FAQEntry(id: "faq_backup"),
            FAQEntry(id: "faq_export"),
            FAQEntry(id: "faq_applock"),
            FAQEntry(id: "faq_cameras_privacy"),
        ]),
    ]
}

struct HelpFAQView: View {
    @State private var search = ""
    @State private var expanded: Set<String> = []

    private var sections: [FAQSection] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return FAQCatalog.sections }
        return FAQCatalog.sections.compactMap { section in
            let hits = section.entries.filter {
                $0.questionText.localizedCaseInsensitiveContains(search) ||
                $0.answerText.localizedCaseInsensitiveContains(search)
            }
            return hits.isEmpty ? nil : FAQSection(id: section.id, icon: section.icon,
                                                   tint: section.tint, entries: hits)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {

                searchBar

                if sections.isEmpty {
                    EmptyStateView(icon: "questionmark.magnifyingglass",
                                   title: "No results",
                                   message: "faq_no_results_hint")
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppSpacing.xl)
                } else {
                    ForEach(sections) { section in
                        sectionView(section)
                    }
                }

                contactCard

                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Help & FAQ")
        .navigationBarTitleDisplayMode(.large)
        .scrollDismissesKeyboard(.interactively)
        .animation(.smooth(duration: 0.25), value: search)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.subheadline)
                .foregroundStyle(.secondary)
            TextField(String(localized: "faq_search_prompt"), text: $search)
                .font(AppFont.scaled(16))
                .submitLabel(.search)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(16))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .glassRoundedRect(14)
    }

    // MARK: - Sections

    private func sectionView(_ section: FAQSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(AppFont.captionStrong)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(section.tint)
                Text(section.title)
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .tracking(0.5)
            }
            .padding(.leading, AppSpacing.xxs)

            VStack(spacing: 0) {
                ForEach(section.entries) { entry in
                    entryRow(entry, tint: section.tint,
                             isLast: entry.id == section.entries.last?.id)
                }
            }
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
    }

    private func entryRow(_ entry: FAQEntry, tint: Color, isLast: Bool) -> some View {
        let isOpen = expanded.contains(entry.id)
        return VStack(spacing: 0) {
            Button {
                HapticFeedback.selection()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(entry.question)
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: AppSpacing.sm)
                    Image(systemName: "chevron.down")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(isOpen ? tint : Color.primary.opacity(0.35))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.base)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOpen ? [.isButton, .isSelected] : .isButton)

            if isOpen {
                Text(entry.answer)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.primary.opacity(0.65))
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.base)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !isLast {
                Rectangle().fill(Color.primary.opacity(0.05))
                    .frame(height: 0.5).padding(.leading, AppSpacing.lg)
            }
        }
    }

    // MARK: - Contact

    private var contactCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.open.fill")
                .font(AppFont.scaled(26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 56, height: 56)
                .glassCircle()
            VStack(spacing: 4) {
                Text("Still need help?")
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                Text("faq_support_note")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .multilineTextAlignment(.center)
            }
            Button {
                if let url = URL(string: "mailto:support@prvio.app") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Email Support", systemImage: "envelope.fill")
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.base)
                    .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                interactive: true)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .liquidGlass(cornerRadius: AppRadius.xl, thick: true)
        .padding(.top, AppSpacing.sm)
    }
}
