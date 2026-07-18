import SwiftUI

// MARK: - Plant health (Plant OS P4, Level 4 — ailments + guided diagnosis)
//
// A pushed page with two honest surfaces:
//   • Guided diagnosis — a grouped symptom checklist feeding a transparent,
//     offline decision tree. Results are ranked "possible matches", each
//     showing exactly which symptoms it explains, its severity, treatment and
//     prevention, and its sources. Never a definitive verdict.
//   • Ailments reference — browse/search the whole knowledge base; tap through
//     to the full profile.
//
// AI photo diagnosis is intentionally NOT offered: the app has no verified
// vision pipeline that accepts images (the ARIA chat path is text-only). Per
// the honesty law we surface the guided path as the diagnosis story and show
// an explanatory note rather than a fake "AI" button or a fabricated
// confidence figure. When a real vision model is wired in, a gated entry point
// can be added here.

struct PlantHealthView: View {
    let service: PlantAilmentService
    /// The plant's linked species (susceptibility boost only), if any.
    var speciesId: UUID? = nil
    /// The plant's display name, for context in copy.
    var speciesName: String? = nil

    @State private var mode: Mode = .diagnose
    @State private var selectedTags: Set<String> = []
    @State private var search = ""

    enum Mode: String, CaseIterable, Identifiable {
        case diagnose, reference
        var id: String { rawValue }
        var titleKey: LocalizedStringKey {
            self == .diagnose ? "plant_health_mode_diagnose" : "plant_health_mode_reference"
        }
    }

    private var matches: [PlantAilmentService.DiagnosisMatch] {
        service.diagnose(tags: selectedTags, speciesId: speciesId)
    }

    private var referenceResults: [PlantAilment] {
        service.search(search)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: AppSpacing.lg) {
                modePicker

                if mode == .diagnose {
                    Group {
                        susceptibilityCard
                        symptomChecklistCard
                        diagnosisResults
                        aiDeferredNote
                    }
                } else {
                    referenceList
                }

                Spacer(minLength: AppSpacing.xxl)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
        }
        .navigationTitle(Text("plant_health_title"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(AppMotion.state, value: selectedTags)
        .animation(AppMotion.state, value: mode)
        .task { await service.loadAll() }
    }

    // MARK: Mode picker

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases) { m in
                Text(m.titleKey).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Known risks for this plant (susceptibility)

    @ViewBuilder
    private var susceptibilityCard: some View {
        let risks = service.susceptibilities(forSpecies: speciesId)
        if !risks.isEmpty {
            sectionCard("plant_health_known_risks", icon: "exclamationmark.shield") {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    Text("plant_health_known_risks_sub")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(risks, id: \.ailment.id) { risk in
                        NavigationLink {
                            PlantAilmentDetailView(ailment: risk.ailment)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: risk.ailment.kindIcon)
                                    .font(AppFont.caption)
                                    .foregroundStyle(risk.ailment.severityColor)
                                    .frame(width: 26, height: 26)
                                    .background(risk.ailment.severityColor.opacity(AppOpacity.tintedFill), in: Circle())
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(risk.ailment.localizedCommonName)
                                        .font(AppFont.footnoteEmphasis)
                                        .foregroundStyle(.primary)
                                    if let note = risk.note, !note.isEmpty {
                                        Text(note)
                                            .font(AppFont.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                Spacer(minLength: AppSpacing.sm)
                                Image(systemName: "chevron.right")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.primary.opacity(0.28))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Symptom checklist

    private var symptomChecklistCard: some View {
        sectionCard("plant_health_symptoms", icon: "checklist") {
            VStack(alignment: .leading, spacing: AppSpacing.base) {
                Text("plant_health_symptoms_sub")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(PlantSymptomGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Label(group.titleKey, systemImage: group.icon)
                            .font(AppFont.label)
                            .foregroundStyle(.secondary)
                        SymptomFlow(spacing: AppSpacing.sm) {
                            ForEach(PlantSymptomCatalog.inGroup(group)) { symptom in
                                SymptomChip(
                                    symptom: symptom,
                                    isOn: selectedTags.contains(symptom.tag)
                                ) { toggle(symptom.tag) }
                            }
                        }
                    }
                }

                if !selectedTags.isEmpty {
                    Button {
                        HapticFeedback.selection()
                        selectedTags.removeAll()
                    } label: {
                        Label("plant_health_clear", systemImage: "arrow.counterclockwise")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.xxs)
                }
            }
        }
    }

    private func toggle(_ tag: String) {
        HapticFeedback.selection()
        if selectedTags.contains(tag) { selectedTags.remove(tag) }
        else { selectedTags.insert(tag) }
    }

    // MARK: Diagnosis results

    @ViewBuilder
    private var diagnosisResults: some View {
        if selectedTags.isEmpty {
            EmptyStateView(
                icon: "stethoscope",
                title: "plant_health_diag_empty_title",
                message: "plant_health_diag_empty_msg"
            )
        } else if matches.isEmpty {
            EmptyStateView(
                icon: "magnifyingglass",
                title: "plant_health_diag_none_title",
                message: "plant_health_diag_none_msg"
            )
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("plant_health_diag_results")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                ForEach(matches) { match in
                    DiagnosisResultCard(match: match)
                }
                Text("plant_health_diag_disclaimer")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, AppSpacing.xxs)
            }
        }
    }

    // MARK: AI photo diagnosis — honest deferral note

    private var aiDeferredNote: some View {
        GlassCard(padding: AppSpacing.lg) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                Image(systemName: "camera.viewfinder")
                    .font(AppFont.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.subtleFill, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("plant_health_ai_deferred_title")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text("plant_health_ai_deferred_body")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Reference browse

    private var referenceList: some View {
        VStack(spacing: AppSpacing.md) {
            HealthSearchField(text: $search)

            if service.isLoading && service.ailments.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppSpacing.xxl)
            } else if referenceResults.isEmpty {
                EmptyStateView(icon: "magnifyingglass", title: "No results")
            } else {
                ForEach(referenceResults) { ailment in
                    NavigationLink {
                        PlantAilmentDetailView(ailment: ailment)
                    } label: {
                        AilmentRow(ailment: ailment)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Shared card chrome (mirrors PlantEncyclopediaView)

    private func sectionCard<Content: View>(_ title: LocalizedStringKey, icon: String,
                                            @ViewBuilder content: @escaping () -> Content) -> some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Label(title, systemImage: icon)
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Symptom chip

private struct SymptomChip: View {
    let symptom: PlantSymptomTag
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: symptom.icon)
                    .font(AppFont.scaled(11, weight: .medium))
                Text(symptom.labelKey)
                    .font(AppFont.scaled(13, weight: isOn ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? .white : Color.primary.opacity(AppOpacity.emphasis))
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(
                isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.subtleFill),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

// MARK: - Diagnosis result card

private struct DiagnosisResultCard: View {
    let match: PlantAilmentService.DiagnosisMatch

    private var ailment: PlantAilment { match.ailment }

    var body: some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Header: name + kind + strength
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: ailment.kindIcon)
                        .font(AppFont.subheadline)
                        .foregroundStyle(ailment.severityColor)
                        .frame(width: 34, height: 34)
                        .background(ailment.severityColor.opacity(AppOpacity.tintedFill), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ailment.localizedCommonName)
                            .font(AppFont.headline)
                            .foregroundStyle(.primary)
                        HStack(spacing: AppSpacing.xs) {
                            Text(ailment.kindLabelKey)
                            Text("·")
                            Text(ailment.severityLabelKey)
                                .foregroundStyle(ailment.severityColor)
                        }
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: AppSpacing.sm)
                    if match.susceptible {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(AppFont.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(Text("plant_health_susceptible"))
                    }
                }

                // Honest match strength — coverage of the ticked symptoms.
                HStack(spacing: AppSpacing.xs) {
                    Text(match.strengthKey)
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.accentColor)
                    Text(String(format: String(localized: "plant_health_match_fmt"),
                                match.matchedCount, match.selectedCount))
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }

                // Matched symptoms
                matchedSymptoms

                if match.susceptible {
                    Text("plant_health_susceptible_note")
                        .font(AppFont.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                AilmentSectionsView(ailment: ailment, compact: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var matchedSymptoms: some View {
        SymptomFlow(spacing: AppSpacing.xs) {
            ForEach(match.matchedTags, id: \.self) { tag in
                if let entry = PlantSymptomCatalog.entry(for: tag) {
                    HStack(spacing: AppSpacing.xxs) {
                        Image(systemName: "checkmark")
                            .font(AppFont.scaled(9, weight: .bold))
                        Text(entry.labelKey)
                            .font(AppFont.scaled(12))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.brandSuccess)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 5)
                    .background(Color.brandSuccess.opacity(AppOpacity.tintedFill), in: Capsule())
                }
            }
        }
    }
}

// MARK: - Ailment reference row

private struct AilmentRow: View {
    let ailment: PlantAilment

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: ailment.kindIcon)
                .font(AppFont.subheadline)
                .foregroundStyle(ailment.severityColor)
                .frame(width: 40, height: 40)
                .background(ailment.severityColor.opacity(AppOpacity.tintedFill), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(ailment.localizedCommonName)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: AppSpacing.xs) {
                    Text(ailment.kindLabelKey)
                    Text("·")
                    Text(ailment.severityLabelKey)
                        .foregroundStyle(ailment.severityColor)
                }
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: AppSpacing.sm)
            Image(systemName: "chevron.right")
                .font(AppFont.caption)
                .foregroundStyle(Color.primary.opacity(0.28))
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.subtleFill, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Ailment detail

struct PlantAilmentDetailView: View {
    let ailment: PlantAilment

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: AppSpacing.lg) {
                header
                AilmentSectionsView(ailment: ailment, compact: false)
                Spacer(minLength: AppSpacing.xxl)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.lg)
        }
        .navigationTitle(ailment.localizedCommonName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        GlassCard(padding: AppSpacing.lg) {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: ailment.kindIcon)
                    .font(AppFont.title3)
                    .foregroundStyle(ailment.severityColor)
                    .frame(width: 48, height: 48)
                    .background(ailment.severityColor.opacity(AppOpacity.tintedFill), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(ailment.localizedCommonName)
                        .font(AppFont.title3)
                        .foregroundStyle(.primary)
                    if let latin = ailment.latinName, !latin.isEmpty {
                        Text(latin)
                            .font(AppFont.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: AppSpacing.xs) {
                        Text(ailment.kindLabelKey)
                        Text("·")
                        Text(ailment.severityLabelKey)
                            .foregroundStyle(ailment.severityColor)
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Ailment content sections (shared by result card + detail)
//
// Honesty law: only populated fields render. `compact` trims the header
// chrome for embedding inside a diagnosis result card.

struct AilmentSectionsView: View {
    let ailment: PlantAilment
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? AppSpacing.md : AppSpacing.lg) {
            if !compact { listBlock("plant_health_sec_symptoms", icon: "list.bullet", items: ailment.localizedSymptoms) }
            paragraphBlock("plant_health_sec_causes", icon: "questionmark.circle", text: ailment.localizedCauses)
            paragraphBlock("plant_health_sec_treatment", icon: "cross.case", text: ailment.localizedTreatment)
            paragraphBlock("plant_health_sec_prevention", icon: "shield.lefthalf.filled", text: ailment.localizedPrevention)
            sourcesBlock
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func paragraphBlock(_ title: LocalizedStringKey, icon: String, text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label(title, systemImage: icon)
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func listBlock(_ title: LocalizedStringKey, icon: String, items: [String]?) -> some View {
        if let items, !items.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label(title, systemImage: icon)
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var sourcesBlock: some View {
        if let sources = ailment.sources, !sources.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label("plant_health_sec_sources", systemImage: "book.closed")
                    .font(AppFont.label)
                    .foregroundStyle(.secondary)
                Text(sources.joined(separator: " · "))
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Inline search field (reference browse)

private struct HealthSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)
            TextField("plant_health_search", text: $text)
            .font(AppFont.body)
            .foregroundStyle(.primary)
            .tint(.accentColor)
            .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                    HapticFeedback.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .background(Color.subtleFill, in: Capsule())
    }
}

// MARK: - SymptomFlow — a lightweight wrapping layout for chips
//
// A minimal `Layout` (iOS 16+) that lays subviews left-to-right and wraps to
// the next line when the row is full. Avoids the imprecision of forcing
// variable-width chips into a fixed grid.

private struct SymptomFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrange(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: maxWidth == .infinity ? rows.map(\.width).max() ?? 0 : maxWidth,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = arrange(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = subviews[item].sizeThatFits(.unspecified)
                subviews[item].place(at: CGPoint(x: x, y: y),
                                      anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && projected > maxWidth {
                rows.append(current)
                current = Row()
                current.items = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.items.append(index)
                current.width = current.items.count == 1 ? size.width : current.width + spacing + size.width
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
