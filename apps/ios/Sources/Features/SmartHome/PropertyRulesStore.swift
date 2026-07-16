import Foundation
import Observation
import HomeKit
import UserNotifications

// MARK: - Property rules store + evaluation engine (Smart Control R5)
//
// The feature-level home of the PRVIO rules engine: CRUD against
// `property_rules` (RLS: household members), plus the client-side evaluator
// that resolves every enabled rule's condition against LIVE data and
// executes its actions.
//
// HONESTY (stated in the UI too): evaluation runs ONLY while the app is
// open — this is a client-side engine, not 24/7 monitoring. The rules page
// carries that caption verbatim.
//
// Evaluation triggers — composition, zero Services edits:
// - scene-active (the dashboard's existing scenePhase hook calls
//   `evaluateSoon()` next to its IndoorClimateStore refresh);
// - after every IndoorClimateStore refresh and IoTService poll, via ONE
//   Observation tracking on `IndoorClimateStore.readings` and
//   `IoTService.sensors` — the exact signals R4's history mirroring rides.
//   The same tracking also reads `HomePresenceService.lastTransition` (the
//   geofence signal) and the documents list once a source exists.
//   Bursts coalesce through a short debounce; one evaluation pass runs at
//   a time.
// - a minute-aligned foreground tick, armed ONLY while at least one enabled
//   schedule rule exists and the app is foreground (AppLifecycle) — it just
//   calls `evaluateSoon()`. No BGTaskScheduler; the engine stays honest
//   about being app-open-only.
//
// Schedule semantics (catch-up, not pretend-background):
// - the most recent occurrence ≤ now is computed with Calendar.current date
//   components (never epoch arithmetic — DST);
// - the rule matches iff that occurrence is within a 24 h grace window AND
//   `last_fired_at` predates it (nil = match). Opening the app Saturday
//   morning fires Friday-18:00 once, honestly late; opening Monday finds
//   the grace expired and stays quiet. The server-side claim below still
//   dedups devices.
//
// Cooldown semantics — `cooldown_minutes` vs `last_fired_at`:
// - a rule fires only when `last_fired_at` is NULL or older than the
//   cooldown;
// - firing CLAIMS the slot on the server first: a conditional UPDATE
//   (`… WHERE id = ? AND (last_fired_at IS NULL OR last_fired_at < cutoff)
//   RETURNING id`), so two signed-in devices racing the same crossing
//   resolve to one winner — the loser's claim matches zero rows and it
//   stands down;
// - if the claim can't reach the server (offline), the rule still fires
//   once — the engine is client-side and a local notification is still
//   worth having — and a session-local shadow of last-fired keeps it from
//   looping until connectivity returns.
//
// Every firing appends to a local ring buffer (UserDefaults, last 50) that
// the rules page renders as "Istoric declanșări".
/// The store's own failure vocabulary (file-scope so the nonisolated
/// `LocalizedError` requirement never fights the store's actor isolation).
enum RuleStoreError: LocalizedError {
    case noProperty
    var errorDescription: String? { String(localized: "rule_error_no_property") }
}

@MainActor
@Observable
final class PropertyRulesStore {
    static let shared = PropertyRulesStore()

    // MARK: State

    private(set) var rules: [PropertyRule] = []
    private(set) var isLoading = false
    /// The property the current `rules` belong to (nil before first load).
    private(set) var loadedPropertyId: UUID?
    var error: String?
    /// Newest-first firing history (capped at `logCapacity`).
    private(set) var firingLog: [RuleFiringRecord] = []
    /// Rules whose enabled-toggle write is in flight (their toggle disables).
    private(set) var pendingToggleIds: Set<UUID> = []

    var enabledCount: Int { rules.filter(\.enabled).count }

    // MARK: Tunables

    /// Explicit row cap (constitution P0-D — PostgREST truncates silently
    /// without one). A household will realistically hold a handful of rules.
    private static let queryLimit = 200
    private static let logKey = "prvio.rules.firingLog"
    private static let logCapacity = 50
    /// Cached weather older than this is not trusted to fire a rule — the
    /// dashboard refreshes the cache hourly while the app is used, so a 3 h
    /// horizon only bites when weather genuinely stopped loading.
    private static let weatherMaxAge: TimeInterval = 3 * 3600
    /// Poll/refresh bursts coalesce into one evaluation pass.
    private static let evaluateDebounce: Duration = .milliseconds(1200)
    /// How long a missed schedule occurrence stays worth firing (the honest
    /// catch-up window described in the header).
    private static let scheduleGraceWindow: TimeInterval = 24 * 3600
    /// A geofence transition older than this is history, not a signal — a
    /// stale arrive/leave must never fire on a later app-open.
    private static let presenceFreshWindow: TimeInterval = 600

    // MARK: Private plumbing

    private var evaluateTask: Task<Void, Never>?
    private var isEvaluating = false
    private var signalsArmed = false
    /// Session-local last-fired shadow — the offline fallback described in
    /// the header (server `last_fired_at` remains the shared authority).
    private var localLastFired: [UUID: Date] = [:]
    /// The app's shared TaskService when a surface adopted it (so a created
    /// task appears instantly in the open task list); otherwise a private
    /// instance whose `addTask` insert reaches every device via realtime.
    private var adoptedTaskService: TaskService?
    private var fallbackTaskService: TaskService?
    /// Same adoption pattern for documents (the docExpiry condition's data
    /// source): the environment's DocumentService when a surface handed it
    /// over — usually already loaded — otherwise a private instance loaded
    /// on demand.
    private var adoptedDocumentService: DocumentService?
    private var fallbackDocumentService: DocumentService?
    /// One-shot document load bookkeeping — `ensureDocumentsLoaded()`.
    private var documentsLoadTask: Task<Void, Never>?
    private var documentsLoadedOnce = false
    /// The foreground minute tick that keeps schedule rules punctual while
    /// the app is open — nil whenever it isn't needed (or backgrounded).
    private var scheduleTickTask: Task<Void, Never>?

    private init() {
        firingLog = Self.loadLog()
    }

    /// Lets a surface hand over the environment's TaskService instance —
    /// rule-created tasks then land in the very list the Tasks tab shows.
    func adopt(taskService: TaskService) {
        adoptedTaskService = taskService
    }

    /// Lets a surface hand over the environment's DocumentService instance —
    /// docExpiry rules then evaluate the very list the Documents tab shows.
    func adopt(documentService: DocumentService) {
        adoptedDocumentService = documentService
    }

    private var taskService: TaskService {
        if let adoptedTaskService { return adoptedTaskService }
        if let fallbackTaskService { return fallbackTaskService }
        let created = TaskService()
        fallbackTaskService = created
        return created
    }

    private var documentService: DocumentService {
        if let adoptedDocumentService { return adoptedDocumentService }
        if let fallbackDocumentService { return fallbackDocumentService }
        let created = DocumentService()
        fallbackDocumentService = created
        return created
    }

    /// Whether a docExpiry condition can be answered honestly RIGHT NOW: a
    /// documents source already holds rows, or a load attempt completed (an
    /// empty list after a completed load is known-empty, exactly what the
    /// Documents tab would show).
    private var documentsKnown: Bool {
        if let service = adoptedDocumentService ?? fallbackDocumentService,
           !service.documents.isEmpty { return true }
        return documentsLoadedOnce
    }

    // MARK: - Loading

    /// Loads the active property's rules once (and again when the active
    /// property changes) — the cheap call every surface uses.
    func loadIfNeeded() async {
        guard let propertyId = PropertyService.activePropertyId,
              propertyId != loadedPropertyId else { return }
        await load(propertyId: propertyId)
    }

    func load(propertyId: UUID) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [PropertyRule] = try await supabase.from("property_rules")
                .select()
                .eq("property_id", value: propertyId.uuidString)
                .order("created_at", ascending: true)
                .limit(Self.queryLimit)
                .execute().value
            rules = rows
            loadedPropertyId = propertyId
            armSignalsIfNeeded()
            evaluateSoon()
        } catch {
            if error is CancellationError { return }
            // Don't throw an alert over data already on screen.
            if rules.isEmpty { self.error = error.localizedDescription }
        }
    }

    // MARK: - CRUD

    @discardableResult
    func create(name: String, condition: RuleCondition, actions: [RuleAction],
                cooldownMinutes: Int) async throws -> PropertyRule {
        guard let propertyId = loadedPropertyId ?? PropertyService.activePropertyId else {
            throw RuleStoreError.noProperty
        }
        let row = NewPropertyRuleRow(propertyId: propertyId, name: name,
                                     enabled: true, condition: condition,
                                     actions: actions,
                                     cooldownMinutes: cooldownMinutes)
        let created: PropertyRule = try await supabase.from("property_rules")
            .insert(row)
            .select()
            .single()
            .execute().value
        rules.append(created)
        armSignalsIfNeeded()
        evaluateSoon()
        return created
    }

    func update(_ rule: PropertyRule, name: String, condition: RuleCondition,
                actions: [RuleAction], cooldownMinutes: Int) async throws {
        let patch = PropertyRuleUpdate(name: name, condition: condition,
                                       actions: actions,
                                       cooldownMinutes: cooldownMinutes,
                                       updatedAt: ISODate.string(from: Date()))
        let updated: PropertyRule = try await supabase.from("property_rules")
            .update(patch)
            .eq("id", value: rule.id.uuidString)
            .select()
            .single()
            .execute().value
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = updated
        }
        evaluateSoon()
    }

    /// Writes the enabled flag through immediately (optimistic, reverted on
    /// failure); the row's toggle disables while the write is in flight.
    func setEnabled(_ enabled: Bool, for rule: PropertyRule) async {
        guard !pendingToggleIds.contains(rule.id),
              let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        pendingToggleIds.insert(rule.id)
        defer { pendingToggleIds.remove(rule.id) }
        let previous = rules[index].enabled
        rules[index].enabled = enabled
        struct EnabledPatch: Encodable {
            let enabled: Bool
            let updated_at: String
        }
        do {
            try await supabase.from("property_rules")
                .update(EnabledPatch(enabled: enabled,
                                     updated_at: ISODate.string(from: Date())))
                .eq("id", value: rule.id.uuidString)
                .execute()
            if enabled { evaluateSoon() }
        } catch {
            if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[idx].enabled = previous
            }
            self.error = error.localizedDescription
        }
    }

    func delete(_ rule: PropertyRule) async {
        do {
            try await supabase.from("property_rules")
                .delete()
                .eq("id", value: rule.id.uuidString)
                .execute()
            rules.removeAll { $0.id == rule.id }
            localLastFired[rule.id] = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Live sensor universe (engine + builder share it)

    /// Every REAL live reading a rule can watch: HomeKit indoor-climate
    /// readings (temperature always, humidity when reported) under their R4
    /// mirror ids, plus IoT hub sensors currently carrying a fresh numeric
    /// value. Nothing here is ever invented or padded.
    var sensorOptions: [RuleSensorOption] {
        var out: [RuleSensorOption] = []
        for reading in IndoorClimateStore.shared.readings {
            out.append(RuleSensorOption(
                id: IoTService.homeKitSensorId(accessory: reading.id, metric: "temperature"),
                name: reading.accessoryName,
                zone: reading.roomName,
                metric: "temperature",
                unit: "°C",
                value: reading.celsius))
            if let humidity = reading.humidity {
                out.append(RuleSensorOption(
                    id: IoTService.homeKitSensorId(accessory: reading.id, metric: "humidity"),
                    name: reading.accessoryName,
                    zone: reading.roomName,
                    metric: "humidity",
                    unit: "%",
                    value: humidity))
            }
        }
        for sensor in IoTService.shared.sensors {
            guard let value = sensor.value,
                  !SensorFreshness.isStale(sensor.lastUpdated) else { continue }
            out.append(RuleSensorOption(
                id: sensor.stableRef,
                name: sensor.name,
                zone: sensor.linkedZoneName.isEmpty ? nil : sensor.linkedZoneName,
                metric: sensor.type.rawValue,
                unit: sensor.unit.isEmpty ? sensor.type.defaultUnit : sensor.unit,
                value: value))
        }
        return out
    }

    /// Resolves a stored `sensorId` to its CURRENT reading, or nil when the
    /// sensor isn't reporting here right now (the rule is then honestly not
    /// evaluated — never guessed). Accepts a bare IoT sensor UUID
    /// defensively, alongside the canonical identities.
    func resolvedReading(sensorId: String) -> RuleSensorOption? {
        if let hit = sensorOptions.first(where: { $0.id == sensorId }) { return hit }
        // Defensive: a rule written with the sensor's volatile UUID.
        guard let sensor = IoTService.shared.sensors.first(where: { $0.id.uuidString == sensorId }),
              let value = sensor.value,
              !SensorFreshness.isStale(sensor.lastUpdated) else { return nil }
        return RuleSensorOption(
            id: sensorId,
            name: sensor.name,
            zone: sensor.linkedZoneName.isEmpty ? nil : sensor.linkedZoneName,
            metric: sensor.type.rawValue,
            unit: sensor.unit.isEmpty ? sensor.type.defaultUnit : sensor.unit,
            value: value)
    }

    // MARK: - Weather (the cached real weather, freshness-gated)

    struct WeatherSnapshot {
        let temp: Double
        let lo: Double
        let symbol: String
    }

    /// The cached Apple Weather summary, only while it is recent enough to
    /// stand behind — nil gates the weather path off everywhere (builder,
    /// templates, evaluation), honestly.
    var weatherSnapshot: WeatherSnapshot? {
        guard let cached = PropertyWeather.cached(),
              Date().timeIntervalSince(cached.fetchedAt) <= Self.weatherMaxAge else { return nil }
        return WeatherSnapshot(temp: cached.temp, lo: cached.lo, symbol: cached.symbol)
    }

    var weatherAvailable: Bool { weatherSnapshot != nil }

    /// Only states the summary can truthfully answer (see RuleWeatherState):
    /// rain/snow from the current condition's own symbol, frost when the
    /// current temperature or today's forecast low is below 0 °C.
    static func matches(_ state: RuleWeatherState, weather: WeatherSnapshot) -> Bool {
        switch state {
        case .rain:  weather.symbol.contains("rain") || weather.symbol.contains("drizzle")
        case .snow:  weather.symbol.contains("snow") || weather.symbol.contains("sleet")
        case .frost: weather.temp < 0 || weather.lo < 0
        }
    }

    // MARK: - Evaluation triggers

    /// Debounced entry point — safe to call from every signal; bursts
    /// coalesce into one pass. Every call is also the moment the schedule
    /// tick re-checks whether it should run: the existing scene-active hook
    /// funnels through here, so foreground re-activation re-arms the tick
    /// with zero new lifecycle plumbing.
    func evaluateSoon() {
        updateScheduleTick()
        evaluateTask?.cancel()
        evaluateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.evaluateDebounce)
            guard !Task.isCancelled else { return }
            await self?.evaluate()
        }
    }

    private var hasEnabledScheduleRule: Bool {
        rules.contains { rule in
            if case .schedule = rule.condition { return rule.enabled }
            return false
        }
    }

    /// Arms ONE minute-aligned repeating tick while at least one enabled
    /// schedule rule exists AND the app is foreground; cancels it otherwise.
    /// The tick only calls `evaluateSoon()` — evaluation stays single-path.
    /// On backgrounding it stands itself down at the next wake (the app
    /// must go QUIET in the background — see AppLifecycle); the foreground
    /// scene-active hook re-arms it through `evaluateSoon()`.
    private func updateScheduleTick() {
        guard hasEnabledScheduleRule, !AppLifecycle.isBackgrounded else {
            scheduleTickTask?.cancel()
            scheduleTickTask = nil
            return
        }
        guard scheduleTickTask == nil else { return }
        scheduleTickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Sleep to the NEXT minute boundary via Calendar (not a
                // fixed 60 s stride), so hh:mm rules fire at hh:mm.
                let now = Date()
                let boundary = Calendar.current.nextDate(
                    after: now,
                    matching: DateComponents(second: 0),
                    matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
                try? await Task.sleep(for: .seconds(max(1, boundary.timeIntervalSince(now))))
                if Task.isCancelled { return }
                guard let self else { return }
                if AppLifecycle.isBackgrounded || !self.hasEnabledScheduleRule {
                    self.scheduleTickTask = nil
                    return
                }
                self.evaluateSoon()
            }
        }
    }

    /// One Observation tracking over the two live-data signals R4's history
    /// mirroring rides (IoT polls mutate `sensors`; every IndoorClimateStore
    /// refresh reassigns `readings`) — composition, no Services edits.
    private func armSignalsIfNeeded() {
        guard !signalsArmed else { return }
        signalsArmed = true
        armSignals()
    }

    private func armSignals() {
        withObservationTracking {
            _ = IoTService.shared.sensors
            _ = IndoorClimateStore.shared.readings
            // Geofence transitions observed on THIS device — same
            // composition, no Services edits.
            _ = HomePresenceService.shared.lastTransition?.at
            // Documents (docExpiry) — only once a source exists; never
            // instantiate a service just to watch it.
            if let documents = adoptedDocumentService ?? fallbackDocumentService {
                _ = documents.documents
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.evaluateSoon()
                self.armSignals()
            }
        }
    }

    // MARK: - The evaluation pass

    func evaluate() async {
        guard !isEvaluating, loadedPropertyId != nil, !rules.isEmpty else { return }
        isEvaluating = true
        defer { isEvaluating = false }
        ensureDocumentsLoaded()
        let now = Date()
        for rule in rules where rule.enabled {
            // Resolve against LIVE data; nil = not matched OR honestly not
            // evaluatable right now (absent sensor, stale weather) — both skip.
            guard let detail = liveMatchDetail(for: rule, now: now) else { continue }
            // Cooldown: server timestamp first, session shadow as fallback.
            let cooldown = TimeInterval(max(1, rule.cooldownMinutes)) * 60
            let lastFired = [rule.lastFiredAt, localLastFired[rule.id]]
                .compactMap { $0 }.max()
            if let lastFired, now.timeIntervalSince(lastFired) < cooldown { continue }
            await fire(rule, detail: detail, at: now, cooldown: cooldown)
        }
    }

    /// Loads documents once when an enabled docExpiry rule needs them and
    /// no adopted source has them yet — the on-demand half of the adoption
    /// pattern (mirrors the fallback TaskService, plus the load).
    private func ensureDocumentsLoaded() {
        guard documentsLoadTask == nil, !documentsKnown else { return }
        let needsDocuments = rules.contains { rule in
            if case .docExpiry = rule.condition { return rule.enabled }
            return false
        }
        guard needsDocuments else { return }
        documentsLoadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.documentService.load()
            // A completed attempt makes the source "known" — the same
            // cached-paint + refresh trust the Documents tab itself shows.
            self.documentsLoadedOnce = true
            self.documentsLoadTask = nil
            self.evaluateSoon()
        }
    }

    /// The composed live-value line when the condition currently HOLDS,
    /// nil otherwise. This exact text becomes the notification body, the
    /// task description's second half, and the log detail.
    private func liveMatchDetail(for rule: PropertyRule, now: Date) -> String? {
        switch rule.condition {
        case .sensor(let sensor):
            guard let reading = resolvedReading(sensorId: sensor.sensorId) else { return nil }
            let matched = switch sensor.comparator {
            case .lt: reading.value < sensor.threshold
            case .gt: reading.value > sensor.threshold
            }
            guard matched else { return nil }
            return String(format: String(localized: "rule_notif_sensor_body"),
                          reading.name,
                          reading.valueText,
                          RuleValueText.text(sensor.threshold, unit: reading.unit))
        case .weather(let state):
            guard let weather = weatherSnapshot,
                  Self.matches(state, weather: weather) else { return nil }
            switch state {
            case .rain:
                return String(localized: "rule_notif_rain")
            case .snow:
                return String(localized: "rule_notif_snow")
            case .frost:
                return String(format: String(localized: "rule_notif_frost"),
                              RuleValueText.text(min(weather.temp, weather.lo), unit: "°C"))
            }
        case .schedule(let schedule):
            guard let occurrence = Self.latestOccurrence(of: schedule, before: now) else {
                return nil
            }
            // Grace window: a missed occurrence fires once, honestly late,
            // on app open — but never an ancient one.
            guard now.timeIntervalSince(occurrence) <= Self.scheduleGraceWindow else {
                return nil
            }
            // Once per occurrence: the fire stamp (server or session
            // shadow) must PREDATE the occurrence.
            let lastFired = [rule.lastFiredAt, localLastFired[rule.id]]
                .compactMap { $0 }.max()
            if let lastFired, lastFired >= occurrence { return nil }
            return String(format: String(localized: "rule_notif_schedule"),
                          occurrence.formatted(date: .abbreviated, time: .shortened))
        case .docExpiry(let days):
            guard documentsKnown else { return nil }
            // The soonest-expiring document inside the horizon carries the
            // detail line (0 = expires today; negatives are already past).
            let candidates: [(doc: DocumentModel, left: Int)] =
                documentService.documents.compactMap { doc in
                    guard let left = doc.daysUntilExpiry,
                          (0...days).contains(left) else { return nil }
                    return (doc, left)
                }
            guard let soonest = candidates.min(by: { $0.left < $1.left }) else { return nil }
            switch soonest.left {
            case 0:
                return String(format: String(localized: "rule_notif_doc_expiry_today"),
                              soonest.doc.name)
            case 1:
                return String(format: String(localized: "rule_notif_doc_expiry_tomorrow"),
                              soonest.doc.name)
            default:
                return String(format: String(localized: "rule_notif_doc_expiry_days"),
                              soonest.doc.name, soonest.left)
            }
        case .geofence(let event):
            // Only a FRESH transition of the watched kind, and only while
            // monitoring is actually armed — a stale arrive/leave must not
            // fire on a later app-open.
            guard HomePresenceService.shared.isArmed,
                  let transition = HomePresenceService.shared.lastTransition,
                  transition.kind.rawValue == event.rawValue,
                  now.timeIntervalSince(transition.at) < Self.presenceFreshWindow else {
                return nil
            }
            let key: String.LocalizationValue = event == .arrive
                ? "rule_notif_arrive" : "rule_notif_leave"
            return String(localized: key)
        case .unknown:
            return nil // decodes honestly, never evaluated
        }
    }

    /// The most recent occurrence of a schedule at or before `now`, walked
    /// with Calendar date components (NEVER epoch arithmetic) so DST
    /// transitions keep the user's wall-clock time.
    static func latestOccurrence(of schedule: RuleScheduleCondition,
                                 before now: Date) -> Date? {
        // Decode guarantees weekly rows carry a weekday; stay defensive.
        guard schedule.frequency == .daily || schedule.weekday != nil else { return nil }
        var components = DateComponents()
        components.hour = schedule.hour
        components.minute = schedule.minute
        if schedule.frequency == .weekly { components.weekday = schedule.weekday }
        return Calendar.current.nextDate(after: now,
                                         matching: components,
                                         matchingPolicy: .nextTime,
                                         repeatedTimePolicy: .first,
                                         direction: .backward)
    }

    // MARK: - Firing

    private func fire(_ rule: PropertyRule, detail: String, at now: Date,
                      cooldown: TimeInterval) async {
        // Shadow first: whatever happens below, this session won't loop.
        localLastFired[rule.id] = now

        // Claim the cooldown slot on the server — the conditional update
        // returns the row only when THIS device won the race.
        struct FiredPatch: Encodable {
            let last_fired_at: String
            let updated_at: String
        }
        let nowISO = ISODate.string(from: now)
        let cutoffISO = ISODate.string(from: now.addingTimeInterval(-cooldown))
        var claimed = true
        do {
            struct ClaimedRow: Decodable { let id: UUID }
            let won: [ClaimedRow] = try await supabase.from("property_rules")
                .update(FiredPatch(last_fired_at: nowISO, updated_at: nowISO))
                .eq("id", value: rule.id.uuidString)
                .or("last_fired_at.is.null,last_fired_at.lt.\"\(cutoffISO)\"")
                .select("id")
                .execute().value
            claimed = !won.isEmpty
        } catch {
            // Offline claim: fire anyway (client-side engine, the local
            // notification is still worth having); the shadow above stops
            // repeats and the next online firing rewrites the server stamp.
        }
        guard claimed else { return } // another device fired inside the window

        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index].lastFiredAt = now
        }

        var outcomes: [RuleActionOutcome] = []
        for action in rule.actions {
            switch action {
            case .notify:
                outcomes.append(await sendNotification(for: rule, body: detail, at: now))
            case .task(let title):
                outcomes.append(await createTask(title: title, rule: rule, detail: detail))
            case .scene(let home, let actionSet):
                outcomes.append(await runScene(home: home, actionSet: actionSet))
            case .unknown:
                continue // preserved, rendered, never executed
            }
        }
        appendLog(RuleFiringRecord(id: UUID(), ruleId: rule.id,
                                   ruleName: rule.name, firedAt: now,
                                   detail: detail, outcomes: outcomes))
    }

    // MARK: Actions — notification

    /// Permission-honest: respects the user's automation-alerts preference
    /// and the system authorization; a skipped notification is recorded in
    /// the firing log as exactly that, never silently dropped.
    private func sendNotification(for rule: PropertyRule, body: String,
                                  at now: Date) async -> RuleActionOutcome {
        guard NotificationScheduler.prefEnabled(NotificationScheduler.Keys.automationAlerts) else {
            return .notifyOff
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else { return .notifyDenied }
        let content = UNMutableNotificationContent()
        content.title = rule.name
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "rule.\(rule.id.uuidString).\(Int(now.timeIntervalSince1970))",
            content: content,
            trigger: nil)
        do {
            try await center.add(request)
            return .notified
        } catch {
            return .notifyFailed
        }
    }

    /// Asked when the user saves a rule (or template) carrying a notify
    /// action and the system prompt was never shown — the moment consent is
    /// clearly in context. Denied stays denied; the builder says so.
    func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: Actions — maintenance task

    /// Creates a REAL maintenance task through TaskService, duplicate-guarded
    /// per firing: when an open task with the same title already exists for
    /// this property (e.g. the previous firing's task was never completed),
    /// nothing is duplicated and the log says so.
    private func createTask(title: String, rule: PropertyRule,
                            detail: String) async -> RuleActionOutcome {
        guard let propertyId = loadedPropertyId else { return .taskFailed }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .taskFailed }
        do {
            struct OpenRow: Decodable { let id: UUID }
            let existing: [OpenRow] = try await supabase.from("maintenance_tasks")
                .select("id")
                .eq("property_id", value: propertyId.uuidString)
                .eq("title", value: trimmed)
                .in("status", values: ["pending", "in_progress"])
                .limit(1)
                .execute().value
            if !existing.isEmpty { return .taskDuplicate }
        } catch {
            // Can't verify → don't risk a duplicate; the honest outcome.
            return .taskFailed
        }
        let payload = NewTaskPayload(
            propertyId: propertyId,
            title: trimmed,
            description: String(format: String(localized: "rule_task_description"),
                                rule.name, detail),
            dueDate: AppDate.dayString(from: Date()),
            priority: "medium",
            category: "maintenance",
            assigneeIds: [],
            assigneeNames: [])
        do {
            _ = try await taskService.addTask(payload)
            return .taskCreated
        } catch {
            return .taskFailed
        }
    }

    // MARK: Actions — HomeKit scene

    /// Runs the stored scene through the R2 execution path. A scene that no
    /// longer exists (deleted in the Home app, home removed) is reported as
    /// missing — never pretended to run.
    private func runScene(home: UUID, actionSet: UUID) async -> RuleActionOutcome {
        guard let scene = HomeKitService.shared.scenes.first(where: {
            $0.actionSet.uniqueIdentifier == actionSet
                && $0.home.uniqueIdentifier == home
        }) else { return .sceneMissing }
        do {
            try await HomeKitService.shared.executeScene(scene)
            return .sceneRun
        } catch {
            return .sceneFailed
        }
    }

    // MARK: - Firing log (local ring buffer)

    private func appendLog(_ record: RuleFiringRecord) {
        firingLog.insert(record, at: 0)
        if firingLog.count > Self.logCapacity {
            firingLog.removeLast(firingLog.count - Self.logCapacity)
        }
        if let data = try? JSONEncoder().encode(firingLog) {
            UserDefaults.standard.set(data, forKey: Self.logKey)
        }
    }

    private static func loadLog() -> [RuleFiringRecord] {
        guard let data = UserDefaults.standard.data(forKey: logKey),
              let log = try? JSONDecoder().decode([RuleFiringRecord].self, from: data) else {
            return []
        }
        return log
    }

    // MARK: - Display helpers (shared by list rows and the log)

    /// The row's human-readable condition line: "Living · Termostat sub
    /// 5 °C", a weather state's name, or the honest unknown-condition note.
    func conditionSummary(for rule: PropertyRule) -> String {
        switch rule.condition {
        case .sensor(let sensor):
            let reading = resolvedReading(sensorId: sensor.sensorId)
            let name = reading?.name ?? String(localized: "rule_kind_sensor")
            let unit = reading?.unit ?? Self.fallbackUnit(forMetric: sensor.metric)
            let threshold = RuleValueText.text(sensor.threshold, unit: unit)
            let key: String.LocalizationValue = sensor.comparator == .lt
                ? "rule_summary_below" : "rule_summary_above"
            return String(format: String(localized: key), name, threshold)
        case .weather(let state):
            return String(localized: String.LocalizationValue(state.titleKey))
        case .schedule(let schedule):
            // Format the wall-clock time through a real Date so it follows
            // the user's 12/24-hour preference.
            let calendar = Calendar.current
            let time = calendar.date(bySettingHour: schedule.hour,
                                     minute: schedule.minute,
                                     second: 0, of: Date()) ?? Date()
            let timeText = time.formatted(date: .omitted, time: .shortened)
            switch schedule.frequency {
            case .daily:
                return String(format: String(localized: "rule_summary_schedule_daily"),
                              timeText)
            case .weekly:
                return String(format: String(localized: "rule_summary_schedule_weekly"),
                              RuleWeekday.name(schedule.weekday ?? 1), timeText)
            }
        case .docExpiry(let days):
            return String(format: String(localized: "rule_summary_doc_expiry"), days)
        case .geofence(let event):
            let key: String.LocalizationValue = event == .arrive
                ? "rule_summary_geofence_arrive" : "rule_summary_geofence_leave"
            return String(localized: key)
        case .unknown:
            return String(localized: "rule_condition_unknown")
        }
    }

    /// Whether the rule's condition can be answered RIGHT NOW — drives the
    /// quiet "nu se evaluează" note on rows whose sensor is absent, whose
    /// weather cache is missing/stale, whose documents never loaded, or
    /// whose presence monitoring is disarmed.
    func isConditionEvaluatable(_ rule: PropertyRule) -> Bool {
        switch rule.condition {
        case .sensor(let sensor): resolvedReading(sensorId: sensor.sensorId) != nil
        case .weather:            weatherAvailable
        case .schedule:           true // the clock is always live
        case .docExpiry:          documentsKnown
        case .geofence:           HomePresenceService.shared.isArmed
        case .unknown:            false
        }
    }

    /// The stored metric's default unit, for summarizing a rule whose
    /// sensor is temporarily absent (display only — never evaluated).
    private static func fallbackUnit(forMetric metric: String) -> String {
        switch metric {
        case "temperature": "°C"
        case "humidity":    "%"
        default: IoTSensor.SensorType(rawValue: metric)?.defaultUnit ?? ""
        }
    }

    // MARK: - Templates (honest gating)

    /// A one-tap starter offered when the FIRST rule is being created.
    struct RuleTemplate: Identifiable {
        let id: String
        let icon: String
        let titleKey: String
        let captionKey: String
        let condition: RuleCondition
        let actions: [RuleAction]
        let cooldownMinutes: Int

        var name: String { String(localized: String.LocalizationValue(titleKey)) }
    }

    /// The starters THIS estate can honestly run today:
    /// - "Seră sub 5°" only when a greenhouse space exists AND a live
    ///   temperature sensor reports (preferring one attributed to that
    ///   greenhouse);
    /// - the weather starters only while real cached weather is available.
    func templates(zones: [PropertyZone]) -> [RuleTemplate] {
        var out: [RuleTemplate] = []

        if let greenhouse = zones.first(where: { $0.resolvedSpaceKind == .greenhouse }) {
            let temperatures = sensorOptions.filter { $0.metric == "temperature" }
            let preferred = temperatures.first { option in
                guard let zone = option.zone else { return false }
                return zone.trimmingCharacters(in: .whitespacesAndNewlines)
                    .compare(greenhouse.name.trimmingCharacters(in: .whitespacesAndNewlines),
                             options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
            if let sensor = preferred ?? temperatures.first {
                out.append(RuleTemplate(
                    id: "greenhouse-cold",
                    icon: "thermometer.snowflake",
                    titleKey: "rule_template_greenhouse",
                    captionKey: "rule_template_greenhouse_caption",
                    condition: .sensor(RuleSensorCondition(sensorId: sensor.id,
                                                           metric: "temperature",
                                                           comparator: .lt,
                                                           threshold: 5)),
                    actions: [.notify],
                    cooldownMinutes: RuleCooldown.sixHours.rawValue))
            }
        }

        if weatherAvailable {
            out.append(RuleTemplate(
                id: "weather-rain",
                icon: RuleWeatherState.rain.icon,
                titleKey: "rule_template_rain",
                captionKey: "rule_template_rain_caption",
                condition: .weather(.rain),
                actions: [.notify],
                cooldownMinutes: RuleCooldown.sixHours.rawValue))
            out.append(RuleTemplate(
                id: "weather-frost",
                icon: RuleWeatherState.frost.icon,
                titleKey: "rule_template_frost",
                captionKey: "rule_template_frost_caption",
                condition: .weather(.frost),
                actions: [.notify,
                          .task(title: String(localized: "rule_template_frost_task"))],
                cooldownMinutes: RuleCooldown.day.rawValue))
        }

        // "Weekend prep" needs only the clock — always offerable. Friday is
        // Calendar weekday 6 (1 = Sunday … 7 = Saturday, Gregorian).
        out.append(RuleTemplate(
            id: "weekend-prep",
            icon: "calendar.badge.clock",
            titleKey: "rule_template_weekend",
            captionKey: "rule_template_weekend_caption",
            condition: .schedule(RuleScheduleCondition(frequency: .weekly,
                                                       weekday: 6,
                                                       hour: 18, minute: 0)),
            actions: [.task(title: String(localized: "rule_template_weekend_task"))],
            cooldownMinutes: RuleCooldown.day.rawValue))

        // The geofence starter only while presence monitoring is actually
        // armed — same capability gating as the weather starters.
        if HomePresenceService.shared.isArmed {
            out.append(RuleTemplate(
                id: "presence-leave",
                icon: "figure.walk.departure",
                titleKey: "rule_template_presence_leave",
                captionKey: "rule_template_presence_leave_caption",
                condition: .geofence(.leave),
                actions: [.notify],
                cooldownMinutes: RuleCooldown.oneHour.rawValue))
        }

        return out
    }
}
