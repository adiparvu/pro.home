import SwiftUI

// MARK: - Rules page (Smart Control R5)
//
// The rules engine's one surface: the rule list (enabled toggle writing
// through, human-readable condition summary, last-fired relative time,
// swipe delete), the honest client-side caption ("Regulile se evaluează cât
// timp aplicația e deschisă." — always visible, because that IS the
// engine's contract), the template starters when the first rule is being
// created (gated on what this estate can honestly run), and the local
// firing history ("Istoric declanșări").
//
// Presented as a sheet from the hub's "Reguli" row and the dashboard's
// rules row; the builder handles create and edit.
struct PropertyRulesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(TaskService.self) private var taskService

    private let store = PropertyRulesStore.shared

    /// One nested-presentation slot (create or edit) — the app's single
    /// `sheet(item:)` discipline, so presentations never race.
    private enum BuilderContext: Identifiable {
        case create
        case edit(PropertyRule)

        var id: String {
            switch self {
            case .create:          "create"
            case .edit(let rule):  "edit-\(rule.id.uuidString)"
            }
        }
    }

    @State private var builder: BuilderContext? = nil
    /// Template whose one-tap creation is in flight (its row shows progress).
    @State private var creatingTemplateId: String? = nil
    @State private var templateError: String? = nil

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.lg)
                // The engine's honest contract, always on the page.
                Text("rule_honesty_caption")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.xxs)
                content
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $builder) { context in
            switch context {
            case .create:
                PropertyRuleBuilderSheet()
            case .edit(let rule):
                PropertyRuleBuilderSheet(existing: rule)
            }
        }
        .task {
            store.adopt(taskService: taskService)
            await store.loadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            store.evaluateSoon()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.error != nil || templateError != nil },
            set: { if !$0 { store.error = nil; templateError = nil } }
        )) {
            Button("OK", role: .cancel) { store.error = nil; templateError = nil }
        } message: {
            Text(verbatim: store.error ?? templateError ?? "")
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: AppSpacing.sm) {
            Text("rule_hub_title")
                .font(AppFont.scaled(26, weight: .light))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button {
                HapticFeedback.impact(.light)
                builder = .create
            } label: {
                Image(systemName: "plus")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(Text("rule_add"))
            Button {
                HapticFeedback.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(Text("sh_close"))
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if store.isLoading && store.rules.isEmpty {
            Spacer()
            HStack { Spacer(); ProgressView(); Spacer() }
            Spacer()
        } else {
            List {
                if store.rules.isEmpty {
                    emptySection
                    templatesSection
                } else {
                    rulesSection
                }
                logSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: Rules

    private var rulesSection: some View {
        Section {
            ForEach(store.rules) { rule in
                ruleRow(rule)
                    .listRowBackground(rowBackground)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            HapticFeedback.warning()
                            Task { await store.delete(rule) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }

    private func ruleRow(_ rule: PropertyRule) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            Button {
                guard rule.isEditable else { return }
                HapticFeedback.impact(.light)
                builder = .edit(rule)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: rule.name)
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(rule.enabled ? AnyShapeStyle(.primary)
                                                      : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                    Text(verbatim: store.conditionSummary(for: rule))
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if rule.enabled, !store.isConditionEvaluatable(rule) {
                        // The condition can't be answered right now (absent
                        // sensor / stale weather) — say so, quietly.
                        Text(unevaluatableNote(for: rule))
                            .font(AppFont.caption2)
                            .foregroundStyle(Color.brandWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    lastFiredLine(rule)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(rule.isEditable ? Text("rule_row_edit_hint") : Text(verbatim: ""))

            Toggle(isOn: Binding(
                get: { rule.enabled },
                set: { on in Task { await store.setEnabled(on, for: rule) } }
            )) {
                Text(verbatim: rule.name)
            }
            .labelsHidden()
            .disabled(store.pendingToggleIds.contains(rule.id))
            .tint(Color.brandSuccess)
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    @ViewBuilder private func lastFiredLine(_ rule: PropertyRule) -> some View {
        if let firedAt = rule.lastFiredAt {
            Text("rule_last_fired \(firedAt.formatted(.relative(presentation: .named)))")
                .font(AppFont.caption2)
                .foregroundStyle(.tertiary)
        } else {
            Text("rule_never_fired")
                .font(AppFont.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func unevaluatableNote(for rule: PropertyRule) -> LocalizedStringKey {
        switch rule.condition {
        case .weather: "rule_weather_unavailable_short"
        default:       "rule_sensor_unavailable_short"
        }
    }

    // MARK: Empty state + templates (first rule)

    private var emptySection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text("rule_empty_title")
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                Text("rule_empty_caption")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, AppSpacing.xxs)
            .listRowBackground(rowBackground)
        }
    }

    @ViewBuilder private var templatesSection: some View {
        let templates = store.templates(zones: zoneService.zones)
        if !templates.isEmpty {
            Section {
                ForEach(templates) { template in
                    templateRow(template)
                        .listRowBackground(rowBackground)
                }
            } header: {
                Text("rule_templates_header")
                    .font(AppFont.label)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("rule_templates_caption")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func templateRow(_ template: PropertyRulesStore.RuleTemplate) -> some View {
        Button {
            HapticFeedback.impact(.light)
            createFromTemplate(template)
        } label: {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: template.icon)
                    .font(AppFont.headline)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(template.titleKey))
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(.primary)
                    Text(LocalizedStringKey(template.captionKey))
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AppSpacing.sm)
                if creatingTemplateId == template.id {
                    ProgressView()
                } else {
                    Image(systemName: "plus.circle")
                        .font(AppFont.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(creatingTemplateId != nil)
        .accessibilityElement(children: .combine)
    }

    private func createFromTemplate(_ template: PropertyRulesStore.RuleTemplate) {
        creatingTemplateId = template.id
        Task { @MainActor in
            defer { creatingTemplateId = nil }
            do {
                _ = try await store.create(name: template.name,
                                           condition: template.condition,
                                           actions: template.actions,
                                           cooldownMinutes: template.cooldownMinutes)
                await store.requestNotificationPermissionIfNeeded()
                HapticFeedback.success()
            } catch {
                HapticFeedback.error()
                templateError = error.localizedDescription
            }
        }
    }

    // MARK: Firing log

    @ViewBuilder private var logSection: some View {
        if !store.firingLog.isEmpty {
            Section {
                ForEach(store.firingLog) { record in
                    logRow(record)
                        .listRowBackground(rowBackground)
                }
            } header: {
                Text("rule_log_header")
                    .font(AppFont.label)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func logRow(_ record: RuleFiringRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                Text(verbatim: record.ruleName)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.sm)
                Text(record.firedAt, format: .relative(presentation: .named))
                    .font(AppFont.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(verbatim: record.detail)
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if !outcomesLine(record).isEmpty {
                Text(verbatim: outcomesLine(record))
                    .font(AppFont.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, AppSpacing.xxs)
        .accessibilityElement(children: .combine)
    }

    /// "Notificare trimisă · Sarcină creată" — the localized outcome trail;
    /// tokens from newer versions are skipped rather than guessed.
    private func outcomesLine(_ record: RuleFiringRecord) -> String {
        record.outcomes
            .compactMap { outcome in
                outcome.titleKey.map { String(localized: String.LocalizationValue($0)) }
            }
            .joined(separator: " · ")
    }

    // MARK: Row chrome

    /// The FormGroup material, so list rows read as the app's glass cards.
    private var rowBackground: Color {
        Color.primary.opacity(0.04)
    }
}
