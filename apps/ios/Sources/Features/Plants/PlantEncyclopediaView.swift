import SwiftUI

// MARK: - Plant encyclopedia (Plant OS P2, Level 2 — botanical profile)
//
// A pushed page that renders one `PlantSpeciesEntry` from the shared
// knowledge base. Honesty law: only populated sections render — a nil or
// empty field produces no row, no card, no placeholder. Sections appear in a
// fixed reading order (identity → habitat → form → leaves → roots → care
// guides → lore → sources) as Liquid Glass cards.

struct PlantEncyclopediaView: View {
    let entry: PlantSpeciesEntry

    var body: some View {
        ScrollView(showsIndicators: false) {
            // Two Groups keep each ViewBuilder block within its 10-child limit;
            // Group is transparent to the LazyVStack, so laziness is preserved.
            LazyVStack(spacing: AppSpacing.lg) {
                Group {
                    identificationCard
                    habitatCard
                    characteristicsCard
                    leavesCard
                    rootsCard
                    paragraphCard("plant_enc_sec_propagation", icon: "arrow.triangle.branch", text: entry.propagation)
                    paragraphCard("plant_enc_sec_pruning", icon: "scissors", text: entry.pruning)
                }
                Group {
                    listCard("plant_enc_sec_seasonal", icon: "calendar.badge.clock", items: entry.seasonalChecklist)
                    calendarCard
                    faqCard
                    listCard("plant_enc_sec_myths", icon: "exclamationmark.bubble", items: entry.myths)
                    listCard("plant_enc_sec_curiosities", icon: "sparkles", items: entry.curiosities)
                    sourcesCard
                }

                Spacer(minLength: AppSpacing.xxl)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
        }
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Identification

    @ViewBuilder
    private var identificationCard: some View {
        let rows: [(LocalizedStringKey, String)] = [
            ("plant_enc_f_common", entry.commonName ?? ""),
            ("plant_enc_f_latin", entry.latinName ?? ""),
            ("plant_enc_f_synonyms", entry.synonyms?.joined(separator: ", ") ?? ""),
            ("plant_enc_f_family", entry.family ?? ""),
            ("plant_enc_f_genus", entry.genus ?? ""),
            ("plant_enc_f_species", entry.species ?? ""),
            ("plant_enc_f_common_ro", entry.commonNamesRo?.joined(separator: ", ") ?? ""),
        ]
        fieldsCard("plant_enc_sec_identification", icon: "leaf.fill", rows: rows)
    }

    // MARK: Natural habitat

    @ViewBuilder
    private var habitatCard: some View {
        let rows: [(LocalizedStringKey, String)] = [
            ("plant_enc_f_origin", entry.origin ?? ""),
            ("plant_enc_f_altitude", entry.altitude ?? ""),
            ("plant_enc_f_native_temp", entry.nativeTemp ?? ""),
            ("plant_enc_f_native_humidity", entry.nativeHumidity ?? ""),
            ("plant_enc_f_habitat", entry.habitatType ?? ""),
        ]
        fieldsCard("plant_enc_sec_habitat", icon: "globe.europe.africa.fill", rows: rows)
    }

    // MARK: Characteristics

    @ViewBuilder
    private var characteristicsCard: some View {
        let evergreen: String = {
            guard let e = entry.evergreen else { return "" }
            return String(localized: e ? "plant_enc_yes" : "plant_enc_no")
        }()
        let rows: [(LocalizedStringKey, String)] = [
            ("plant_enc_f_max_height", entry.maxHeight ?? ""),
            ("plant_enc_f_max_width", entry.maxWidth ?? ""),
            ("plant_enc_f_growth", entry.growthRate ?? ""),
            ("plant_enc_f_lifespan", entry.lifespan ?? ""),
            ("plant_enc_f_evergreen", evergreen),
            ("plant_enc_f_flowering", entry.floweringPeriod ?? ""),
            ("plant_enc_f_fruiting", entry.fruiting ?? ""),
            ("plant_enc_f_fragrance", entry.fragrance ?? ""),
        ]
        fieldsCard("plant_enc_sec_characteristics", icon: "ruler.fill", rows: rows)
    }

    // MARK: Leaves

    @ViewBuilder
    private var leavesCard: some View {
        let rows: [(LocalizedStringKey, String)] = [
            ("plant_enc_f_leaf_size", entry.leafSize ?? ""),
            ("plant_enc_f_leaf_shape", entry.leafShape ?? ""),
            ("plant_enc_f_leaf_colour", entry.leafColour ?? ""),
            ("plant_enc_f_leaf_texture", entry.leafTexture ?? ""),
            ("plant_enc_f_variegation", entry.variegation ?? ""),
            ("plant_enc_f_gloss", entry.gloss ?? ""),
        ]
        fieldsCard("plant_enc_sec_leaves", icon: "leaf", rows: rows)
    }

    // MARK: Roots

    @ViewBuilder
    private var rootsCard: some View {
        let rows: [(LocalizedStringKey, String)] = [
            ("plant_enc_f_root_type", entry.rootType ?? ""),
        ]
        fieldsCard("plant_enc_sec_roots", icon: "point.3.connected.trianglepath.dotted", rows: rows)
    }

    // MARK: Annual calendar

    @ViewBuilder
    private var calendarCard: some View {
        let months = orderedCalendar
        if !months.isEmpty {
            sectionCard("plant_enc_sec_calendar", icon: "calendar") {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(Array(months.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label)
                                .font(AppFont.captionStrong)
                                .foregroundStyle(Color.accentColor)
                            Text(item.note)
                                .font(AppFont.scaled(15))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// The `annual_calendar` map sorted into calendar-month order, with the
    /// month key (stored in English) localized to the user's locale.
    private var orderedCalendar: [(label: String, note: String)] {
        guard let cal = entry.annualCalendar, !cal.isEmpty else { return [] }
        let englishFmt = DateFormatter(); englishFmt.locale = Locale(identifier: "en_US_POSIX")
        let localizedFmt = DateFormatter(); localizedFmt.locale = .current
        let english: [String] = englishFmt.monthSymbols   // always 12 symbols
        let localized: [String] = localizedFmt.monthSymbols
        return cal.map { key, note -> (order: Int, label: String, note: String) in
            guard let idx = english.firstIndex(where: { $0.caseInsensitiveCompare(key) == .orderedSame }) else {
                return (Int.max, key, note)   // unknown key: keep it, sort last
            }
            let label = idx < localized.count ? localized[idx] : key
            return (idx, label, note)
        }
        .sorted { $0.order < $1.order }
        .map { ($0.label, $0.note) }
    }

    // MARK: FAQ

    @ViewBuilder
    private var faqCard: some View {
        if let faq = entry.faq, !faq.isEmpty {
            sectionCard("plant_enc_sec_faq", icon: "questionmark.circle") {
                VStack(alignment: .leading, spacing: AppSpacing.base) {
                    ForEach(Array(faq.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(item.q)
                                .font(AppFont.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.a)
                                .font(AppFont.scaled(15))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: Sources

    @ViewBuilder
    private var sourcesCard: some View {
        if let sources = entry.sources, !sources.isEmpty {
            sectionCard("plant_enc_sec_sources", icon: "book.closed") {
                Text(sources.joined(separator: " · "))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Reusable building blocks

    /// A titled glass card that renders only if any of its label/value rows
    /// carries a non-empty value.
    @ViewBuilder
    private func fieldsCard(_ title: LocalizedStringKey, icon: String,
                            rows: [(LocalizedStringKey, String)]) -> some View {
        let populated = rows.filter { !$0.1.isEmpty }
        if !populated.isEmpty {
            sectionCard(title, icon: icon) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(Array(populated.enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.0)
                                .font(AppFont.label)
                                .foregroundStyle(Color.secondaryTextColor)
                            Text(row.1)
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// A titled glass card of a single free-text paragraph (propagation,
    /// pruning), shown only when the text is present.
    @ViewBuilder
    private func paragraphCard(_ title: LocalizedStringKey, icon: String, text: String?) -> some View {
        if let text, !text.isEmpty {
            sectionCard(title, icon: icon) {
                Text(text)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// A titled glass card of a bulleted list (checklist, myths, curiosities),
    /// shown only when the list is non-empty.
    @ViewBuilder
    private func listCard(_ title: LocalizedStringKey, icon: String, items: [String]?) -> some View {
        if let items, !items.isEmpty {
            sectionCard(title, icon: icon) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                            Image(systemName: "circle.fill")
                                .font(AppFont.scaled(5))
                                .foregroundStyle(Color.accentColor.opacity(0.7))
                                .padding(.top, 6)
                            Text(item)
                                .font(AppFont.scaled(15))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// The shared card chrome: an icon + title header over arbitrary content.
    private func sectionCard<Content: View>(_ title: LocalizedStringKey, icon: String,
                                            @ViewBuilder content: @escaping () -> Content) -> some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Label(title, systemImage: icon)
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.secondaryTextColor)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Species picker (link a plant to its encyclopedia entry)
//
// A searchable list of the whole `plant_species` catalog. The caller owns the
// PlantSpeciesService instance (loaded lazily on the plant page) and receives
// the chosen entry via `onPick`.

struct PlantSpeciesPickerView: View {
    let service: PlantSpeciesService
    var onPick: (PlantSpeciesEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var results: [PlantSpeciesEntry] {
        service.search(search)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: AppSpacing.xs) {
                    if service.isLoading && service.species.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, AppSpacing.xxl)
                    } else if results.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No results")
                    } else {
                        ForEach(results) { entry in
                            row(entry)
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.xl)
            }
            .navigationTitle(Text("plant_enc_picker_title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("plant_enc_search"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await service.loadAll() }
        }
        .sheetGround()
        .presentationDragIndicator(.visible)
    }

    private func row(_ entry: PlantSpeciesEntry) -> some View {
        Button {
            HapticFeedback.selection()
            onPick(entry)
            dismiss()
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "leaf.fill")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.brandSuccess)
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(AppOpacity.hairline), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let latin = entry.latinName, !latin.isEmpty, latin != entry.displayName {
                        Text(latin)
                            .font(AppFont.caption)
                            .italic()
                            .foregroundStyle(Color.secondaryTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: AppSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(0.28))
            }
            .padding(.vertical, AppSpacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
