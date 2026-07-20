import SwiftUI
import UserNotifications

// MARK: - Rule builder (Smart Control R5)
//
// Create and edit share this one FormKit sheet. Everything offered is
// honestly runnable TODAY:
// - the sensor picker lists only REAL live readings (IoT ∪ HomeKit R4 ids),
//   each showing its current value;
// - the weather path appears only while real cached weather exists, and
//   only the states the cache can answer;
// - the presence path is greyed (with the reason, Save held) while home
//   presence monitoring isn't armed — no dead saves;
// - the scene action is offered only when HomeKit scenes exist;
// - Save stays disabled until the rule is fully valid.
struct PropertyRuleBuilderSheet: View {
    /// nil = create; a rule = edit (only ever reached for `isEditable` rows,
    /// so no stored shape can be silently destroyed).
    let existing: PropertyRule?

    @Environment(\.dismiss) private var dismiss

    private let store = PropertyRulesStore.shared
    private let homeKit = HomeKitService.shared
    private let presence = HomePresenceService.shared

    private enum ConditionKind: Hashable {
        case sensor, weather, schedule, docExpiry, presence
    }

    @State private var name: String
    @State private var kind: ConditionKind
    @State private var sensorId: String?
    @State private var comparator: RuleComparator
    /// Free-typed threshold, parsed leniently ("5,5" and "5.5" both land) —
    /// `TextField(value:format:)` can't represent an EMPTY numeric field,
    /// and a new rule must start without a pretended default threshold.
    @State private var thresholdText: String
    @State private var weatherState: RuleWeatherState
    @State private var scheduleFrequency: RuleScheduleFrequency
    /// Calendar weekday number (1 = Sunday … 7 = Saturday, Gregorian) — the
    /// numbering the vocabulary stores.
    @State private var scheduleWeekday: Int
    /// Only the hour:minute components matter — the calendar day is
    /// irrelevant scaffolding for the wheels.
    @State private var scheduleTime: Date
    @State private var docDays: Int
    @State private var presenceEvent: RulePresenceEvent
    @State private var notifyOn: Bool
    @State private var taskOn: Bool
    @State private var taskTitle: String
    @State private var sceneOn: Bool
    @State private var sceneId: UUID?
    @State private var cooldown: RuleCooldown

    @State private var isSaving = false
    @State private var error: String? = nil
    /// Current system notification permission — drives the honest "won't be
    /// able to alert" note when the user keeps notify on while denied.
    @State private var notificationsDenied = false

    init(existing: PropertyRule? = nil) {
        self.existing = existing

        var name = ""
        var kind: ConditionKind = .sensor
        var sensorId: String? = nil
        var comparator: RuleComparator = .lt
        var thresholdText = ""
        var weatherState: RuleWeatherState = .rain
        var scheduleFrequency: RuleScheduleFrequency = .daily
        // Today's weekday feels like the natural weekly starting point.
        var scheduleWeekday = Calendar.current.component(.weekday, from: Date())
        var scheduleTime = Calendar.current.date(bySettingHour: 9, minute: 0,
                                                 second: 0, of: Date()) ?? Date()
        var docDays = 14
        var presenceEvent: RulePresenceEvent = .arrive
        var notifyOn = existing == nil // new rules start with the free action
        var taskOn = false
        var taskTitle = ""
        var sceneOn = false
        var sceneId: UUID? = nil
        var cooldown: RuleCooldown = .oneHour

        if let existing {
            name = existing.name
            cooldown = RuleCooldown.nearest(to: existing.cooldownMinutes)
            switch existing.condition {
            case .sensor(let condition):
                kind = .sensor
                sensorId = condition.sensorId
                comparator = condition.comparator
                thresholdText = condition.threshold.formatted(
                    .number.grouping(.never).precision(.fractionLength(0...2)))
            case .weather(let state):
                kind = .weather
                weatherState = state
            case .schedule(let schedule):
                kind = .schedule
                scheduleFrequency = schedule.frequency
                scheduleWeekday = schedule.weekday ?? scheduleWeekday
                scheduleTime = Calendar.current.date(bySettingHour: schedule.hour,
                                                     minute: schedule.minute,
                                                     second: 0,
                                                     of: Date()) ?? scheduleTime
            case .docExpiry(let days):
                kind = .docExpiry
                docDays = days
            case .geofence(let event):
                kind = .presence
                presenceEvent = event
            case .unknown:
                break // unreachable: unknown rows are not editable
            }
            for action in existing.actions {
                switch action {
                case .notify:
                    notifyOn = true
                case .task(let title):
                    taskOn = true
                    taskTitle = title
                case .scene(_, let actionSet):
                    sceneOn = true
                    sceneId = actionSet
                case .unknown:
                    break
                }
            }
        }

        _name = State(initialValue: name)
        _kind = State(initialValue: kind)
        _sensorId = State(initialValue: sensorId)
        _comparator = State(initialValue: comparator)
        _thresholdText = State(initialValue: thresholdText)
        _weatherState = State(initialValue: weatherState)
        _scheduleFrequency = State(initialValue: scheduleFrequency)
        _scheduleWeekday = State(initialValue: scheduleWeekday)
        _scheduleTime = State(initialValue: scheduleTime)
        _docDays = State(initialValue: docDays)
        _presenceEvent = State(initialValue: presenceEvent)
        _notifyOn = State(initialValue: notifyOn)
        _taskOn = State(initialValue: taskOn)
        _taskTitle = State(initialValue: taskTitle)
        _sceneOn = State(initialValue: sceneOn)
        _sceneId = State(initialValue: sceneId)
        _cooldown = State(initialValue: cooldown)
    }

    // MARK: Derived

    private var sensorOptions: [RuleSensorOption] { store.sensorOptions }

    private var selectedSensor: RuleSensorOption? {
        guard let sensorId else { return nil }
        return store.resolvedReading(sensorId: sensorId)
    }

    private var scenes: [HomeKitScene] { homeKit.scenes }

    private var selectedScene: HomeKitScene? {
        guard let sceneId else { return nil }
        return scenes.first { $0.id == sceneId }
    }

    /// The weather path renders only when it can honestly evaluate — or
    /// while editing an existing weather rule (whose row already carries
    /// the "nu se evaluează" note when the cache is gone).
    private var weatherPathAvailable: Bool {
        if store.weatherAvailable { return true }
        if case .weather? = existing?.condition { return true }
        return false
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The typed threshold as a number — accepts both decimal separators
    /// (the decimal pad follows the locale); nil while invalid/empty.
    private var parsedThreshold: Double? {
        let cleaned = thresholdText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private var hasValidAction: Bool {
        if notifyOn { return true }
        if taskOn, !taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if sceneOn, selectedScene != nil { return true }
        return false
    }

    /// The stored sensor condition while editing — lets a rename/cooldown
    /// edit save even when the rule's sensor isn't reporting at this exact
    /// moment (its identity and metric are already on the row).
    private var storedSensorCondition: RuleSensorCondition? {
        guard case .sensor(let condition)? = existing?.condition else { return nil }
        return condition
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty, hasValidAction else { return false }
        // A half-configured action means the user isn't done — hold Save.
        if taskOn, taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if sceneOn, selectedScene == nil { return false }
        switch kind {
        case .sensor:
            guard parsedThreshold != nil else { return false }
            if selectedSensor != nil { return true }
            // Editing, sensor temporarily silent: the stored identity is
            // still a complete condition.
            return sensorId != nil && sensorId == storedSensorCondition?.sensorId
        case .weather:
            return weatherPathAvailable
        case .schedule:
            return true // the wheels always hold a complete time
        case .docExpiry:
            return docDaysRange.contains(docDays)
        case .presence:
            // No dead saves: a geofence rule needs armed monitoring.
            return presence.isArmed
        }
    }

    /// The stepper's horizon. 1...60 for new rules; an existing row written
    /// with a wider horizon keeps its value reachable instead of being
    /// silently clamped on the next save.
    private var docDaysRange: ClosedRange<Int> {
        var lower = 1, upper = 60
        if case .docExpiry(let days)? = existing?.condition {
            lower = min(lower, max(0, days))
            upper = max(upper, days)
        }
        return lower...upper
    }

    // MARK: Body

    var body: some View {
        FormScaffold(
            title: existing == nil ? "rule_builder_title_new" : "rule_builder_title_edit",
            canSave: canSave,
            isSaving: isSaving,
            error: $error,
            onSave: save
        ) {
            nameGroup
            conditionGroup
            actionsGroup
            cooldownGroup
        }
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationsDenied = settings.authorizationStatus == .denied
        }
        .onChange(of: kind) { _, newKind in
            // Suggest a 24 h cooldown for document expiry — it should nag
            // once a day, not on every evaluation pass. Suggestion only:
            // creating, and freely overridable afterwards.
            if newKind == .docExpiry, existing == nil {
                cooldown = .day
            }
        }
    }

    // MARK: Name

    private var nameGroup: some View {
        FormGroup {
            FormRow(icon: "character.cursor.ibeam", tint: .accentColor) {
                TextField("rule_name_placeholder", text: $name)
                    .font(AppFont.scaled(15))
            }
        }
    }

    // MARK: Condition

    private var conditionGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            FormGroup(title: "rule_section_condition") {
                FormRow(icon: "slider.horizontal.3", tint: .accentColor) {
                    // Five kinds no longer fit a segmented control — the
                    // kind picker is a menu now, and always visible.
                    Picker("rule_section_condition", selection: $kind) {
                        Text("rule_kind_sensor").tag(ConditionKind.sensor)
                        if weatherPathAvailable {
                            Text("rule_kind_weather").tag(ConditionKind.weather)
                        }
                        Text("rule_kind_schedule").tag(ConditionKind.schedule)
                        Text("rule_kind_documents").tag(ConditionKind.docExpiry)
                        Text("rule_kind_presence").tag(ConditionKind.presence)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                FormDivider()
                switch kind {
                case .sensor:    sensorRows
                case .weather:   weatherRows
                case .schedule:  scheduleRows
                case .docExpiry: documentRows
                case .presence:  presenceRows
                }
            }
            if !weatherPathAvailable {
                // Why there is no weather option right now — honest, quiet.
                Text("rule_weather_unavailable")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.xxs)
            }
            if kind == .presence, !presence.isArmed {
                // The pane is greyed and Save held — say why, honestly.
                Text("rule_presence_disarmed")
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }

    @ViewBuilder private var sensorRows: some View {
        if sensorOptions.isEmpty && selectedSensor == nil {
            FormRow(icon: "sensor.tag.radiowaves.forward.fill", tint: .secondary) {
                Text("rule_no_sensors")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            FormRow(icon: "sensor.tag.radiowaves.forward.fill", tint: .accentColor) {
                Picker("rule_kind_sensor", selection: $sensorId) {
                    Text("rule_sensor_choose").tag(String?.none)
                    if let sensorId, selectedSensor == nil,
                       !sensorOptions.contains(where: { $0.id == sensorId }) {
                        // Editing a rule whose sensor isn't reporting right
                        // now: keep its identity selectable (and the Picker's
                        // selection valid) under an honest label.
                        Text("rule_sensor_absent").tag(String?.some(sensorId))
                    }
                    ForEach(sensorOptions) { option in
                        Text(verbatim: option.pickerLabel)
                            .tag(String?.some(option.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            FormDivider()
            FormRow(icon: "arrow.up.arrow.down", tint: .accentColor) {
                Picker("rule_threshold", selection: $comparator) {
                    ForEach(RuleComparator.allCases) { option in
                        Text(LocalizedStringKey(option.titleKey)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            FormDivider()
            FormRow(icon: "number", tint: .accentColor) {
                TextField("rule_threshold", text: $thresholdText)
                    .font(AppFont.scaled(15))
                    .keyboardType(.decimalPad)
                if let unit = selectedSensor?.unit, !unit.isEmpty {
                    Text(verbatim: unit)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let sensor = selectedSensor {
                FormDivider()
                FormRow(icon: "waveform.path.ecg", tint: .secondary) {
                    // The sensor's genuine current value — the builder's
                    // ground truth while choosing a threshold.
                    Text("rule_current_value \(sensor.valueText)")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var weatherRows: some View {
        FormRow(icon: weatherState.icon, tint: .accentColor) {
            Picker("rule_kind_weather", selection: $weatherState) {
                ForEach(RuleWeatherState.allCases) { state in
                    Text(LocalizedStringKey(state.titleKey)).tag(state)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        FormDivider()
        FormRow(icon: "apple.logo", tint: .secondary) {
            // WeatherKit attribution — the states above are answered from
            // Apple Weather data.
            Text(verbatim: " Apple Weather")
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var scheduleRows: some View {
        FormRow(icon: "repeat", tint: .accentColor) {
            Picker("rule_kind_schedule", selection: $scheduleFrequency) {
                ForEach(RuleScheduleFrequency.allCases) { frequency in
                    Text(LocalizedStringKey(frequency.titleKey)).tag(frequency)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        if scheduleFrequency == .weekly {
            FormDivider()
            FormRow(icon: "calendar", tint: .accentColor) {
                // Calendar weekday numbers, presented in the locale's own
                // week order with localized names.
                Picker("rule_schedule_weekday", selection: $scheduleWeekday) {
                    ForEach(RuleWeekday.displayOrder, id: \.self) { weekday in
                        Text(verbatim: RuleWeekday.name(weekday)).tag(weekday)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        FormDivider()
        FormRow(icon: "clock", tint: .accentColor) {
            DatePicker(selection: $scheduleTime, displayedComponents: .hourAndMinute) {
                Text("rule_schedule_time")
                    .font(AppFont.scaled(15))
            }
        }
    }

    @ViewBuilder private var documentRows: some View {
        FormRow(icon: "doc.badge.clock", tint: .accentColor) {
            Stepper(value: $docDays, in: docDaysRange) {
                // Same copy the rule row will show — no surprises later.
                Text(verbatim: String(format: String(localized: "rule_summary_doc_expiry"),
                                      docDays))
                    .font(AppFont.scaled(15))
            }
        }
    }

    @ViewBuilder private var presenceRows: some View {
        FormRow(icon: "location.fill", tint: presence.isArmed ? .accentColor : .secondary) {
            Picker("rule_kind_presence", selection: $presenceEvent) {
                ForEach(RulePresenceEvent.allCases) { event in
                    Text(LocalizedStringKey(event.titleKey)).tag(event)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Greyed until home presence monitoring is armed in Settings —
            // the note under the group says so, and Save stays held.
            .disabled(!presence.isArmed)
        }
    }

    // MARK: Actions

    private var actionsGroup: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            FormGroup(title: "rule_section_actions") {
                FormRow(icon: "bell.fill", tint: .accentColor) {
                    Toggle(isOn: $notifyOn) {
                        Text("rule_action_notify")
                            .font(AppFont.scaled(15))
                    }
                    .tint(Color.brandSuccess)
                }
                FormDivider()
                FormRow(icon: "checklist", tint: .accentColor) {
                    Toggle(isOn: $taskOn.animation(.smooth(duration: 0.25))) {
                        Text("rule_action_task")
                            .font(AppFont.scaled(15))
                    }
                    .tint(Color.brandSuccess)
                }
                if taskOn {
                    FormRow(icon: "character.cursor.ibeam", tint: .secondary) {
                        TextField("rule_task_title_placeholder", text: $taskTitle)
                            .font(AppFont.scaled(15))
                    }
                }
                // The scene action exists only when scenes do — no dead rows.
                if !scenes.isEmpty {
                    FormDivider()
                    FormRow(icon: "sparkles", tint: .accentColor) {
                        Toggle(isOn: $sceneOn.animation(.smooth(duration: 0.25))) {
                            Text("rule_action_scene")
                                .font(AppFont.scaled(15))
                        }
                        .tint(Color.brandSuccess)
                    }
                    if sceneOn {
                        FormRow(icon: "play.circle", tint: .secondary) {
                            Picker("rule_action_scene", selection: $sceneId) {
                                Text("rule_scene_choose").tag(UUID?.none)
                                ForEach(scenes) { scene in
                                    Text(verbatim: scene.name)
                                        .tag(UUID?.some(scene.id))
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            if notifyOn, notificationsDenied {
                // Notifications are off at the system level — the action
                // will be skipped, and the user deserves to know now.
                Text("rule_notify_denied")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.brandWarning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }

    // MARK: Cooldown

    private var cooldownGroup: some View {
        FormGroup(title: "rule_section_cooldown") {
            FormRow(icon: "clock", tint: .accentColor) {
                Picker("rule_section_cooldown", selection: $cooldown) {
                    ForEach(RuleCooldown.allCases) { option in
                        Text(LocalizedStringKey(option.titleKey)).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Save

    private func save() {
        guard canSave, !isSaving else { return }

        let condition: RuleCondition
        switch kind {
        case .sensor:
            guard let threshold = parsedThreshold else { return }
            if let sensor = selectedSensor {
                condition = .sensor(RuleSensorCondition(sensorId: sensor.id,
                                                        metric: sensor.metric,
                                                        comparator: comparator,
                                                        threshold: threshold))
            } else if let stored = storedSensorCondition, sensorId == stored.sensorId {
                // The sensor is momentarily silent — its stored identity
                // and metric remain the truth.
                condition = .sensor(RuleSensorCondition(sensorId: stored.sensorId,
                                                        metric: stored.metric,
                                                        comparator: comparator,
                                                        threshold: threshold))
            } else {
                return
            }
        case .weather:
            condition = .weather(weatherState)
        case .schedule:
            // Only the wall-clock components leave the wheels — the
            // scaffolding Date's calendar day is deliberately dropped.
            let components = Calendar.current.dateComponents([.hour, .minute],
                                                             from: scheduleTime)
            condition = .schedule(RuleScheduleCondition(
                frequency: scheduleFrequency,
                weekday: scheduleFrequency == .weekly ? scheduleWeekday : nil,
                hour: components.hour ?? 0,
                minute: components.minute ?? 0))
        case .docExpiry:
            condition = .docExpiry(days: docDays)
        case .presence:
            guard presence.isArmed else { return } // canSave already holds this
            condition = .geofence(presenceEvent)
        }

        var actions: [RuleAction] = []
        if notifyOn { actions.append(.notify) }
        if taskOn {
            actions.append(.task(title: taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if sceneOn, let scene = selectedScene {
            actions.append(.scene(home: scene.home.uniqueIdentifier, actionSet: scene.id))
        }

        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                if let existing {
                    try await store.update(existing, name: trimmedName,
                                           condition: condition, actions: actions,
                                           cooldownMinutes: cooldown.rawValue)
                } else {
                    _ = try await store.create(name: trimmedName,
                                               condition: condition, actions: actions,
                                               cooldownMinutes: cooldown.rawValue)
                }
                if notifyOn {
                    await store.requestNotificationPermissionIfNeeded()
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                HapticFeedback.error()
                self.error = error.recordableDescription
            }
        }
    }
}
