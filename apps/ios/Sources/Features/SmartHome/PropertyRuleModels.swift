import Foundation

// MARK: - Property rules — the jsonb vocabulary (Smart Control R5)
//
// `public.property_rules` (migration 155) stores one watched CONDITION and
// an ACTIONS array per rule, both as jsonb the APP owns. This file is the
// single authority on those shapes — version-tagged (`"v": 1`) so future
// vocabularies can coexist with rows written today.
//
// Condition (exactly one per rule):
//   {"v":1,"kind":"sensor","sensorId":"…","metric":"temperature",
//    "comparator":"lt"|"gt","threshold":5.0}
//   {"v":1,"kind":"weather","state":"rain"|"snow"|"frost"}
//   {"v":1,"kind":"schedule","freq":"daily"|"weekly","weekday":1-7,
//    "hour":0-23,"minute":0-59}
//   {"v":1,"kind":"docExpiry","days":N}
//   {"v":1,"kind":"geofence","event":"arrive"|"leave"}
//
//   `schedule` carries `weekday` ONLY when freq=="weekly", in
//   `Calendar.current` weekday numbering (1 = Sunday … 7 = Saturday in the
//   Gregorian calendar — the numbering `DateComponents.weekday` uses).
//   Occurrences are always resolved through Calendar date math, never epoch
//   arithmetic, so DST transitions land on the wall-clock time the user set.
//
//   `docExpiry` matches while ANY document's days-until-expiry sits in
//   0...N (today counts). `geofence` rides the on-device HomePresenceService
//   transition signal and only fires on a FRESH transition — a stale one
//   must never fire on a later app-open.
//
//   `sensorId` spans both sensor worlds with the identities R4 already made
//   durable:
//   - IoT hub sensors → `IoTSensor.stableRef` ("{deviceUUID}:{remoteId}") —
//     the same tuple the poller matches on, stable across rediscovery
//     (a bare sensor UUID is also accepted on resolution, defensively);
//   - HomeKit climate sensors → `IoTService.homeKitSensorId` output
//     ("hk:{accessoryUUID}:temperature" / "hk:{accessoryUUID}:humidity"),
//     the exact ids their history accrues under.
//
//   Weather states are ONLY the ones the cached `PropertyWeather.Summary`
//   can truthfully answer: `rain`/`snow` from the current condition symbol,
//   `frost` when the current temperature or today's low is below 0 °C.
//
// Actions (array, order preserved):
//   {"type":"notify"}                                → local notification
//   {"type":"task","title":"…"}                      → maintenance task
//   {"type":"scene","home":"<uuid>","actionSet":"<uuid>"} → HomeKit scene
//
// Unknown `kind`/`type`/`state` values (rows written by a NEWER app) decode
// to `.unknown`, carrying the raw JSON so nothing is ever lost: they render
// honestly as "necunoscut", are never evaluated or executed, and re-encode
// byte-equivalently should the row ever round-trip through this client.
//
// jsonb round-trip sanity (encode → decode), walked through per shape:
// - .sensor(sensorId:"a:b", metric:"temperature", comparator:.lt,
//   threshold:5.0) encodes {"v":1,"kind":"sensor","sensorId":"a:b",
//   "metric":"temperature","comparator":"lt","threshold":5.0}; decoding
//   reads kind=="sensor", all four fields present → identical .sensor.
// - .weather(.frost) encodes {"v":1,"kind":"weather","state":"frost"};
//   decoding reads kind=="weather", state known → identical .weather.
// - .schedule(weekly, weekday:6, 18:00) encodes {"v":1,"kind":"schedule",
//   "freq":"weekly","weekday":6,"hour":18,"minute":0}; decoding reads
//   kind=="schedule", freq known, weekday/hour/minute integral and in
//   range → identical .schedule. Daily omits "weekday" entirely.
// - .docExpiry(days:14) encodes {"v":1,"kind":"docExpiry","days":14} →
//   integral non-negative days → identical .docExpiry.
// - .geofence(.arrive) encodes {"v":1,"kind":"geofence","event":"arrive"}
//   → event known → identical .geofence.
// - .notify encodes {"type":"notify"} → decodes to .notify.
// - .task(title:"T") encodes {"type":"task","title":"T"} → .task("T").
// - .scene(home:H, actionSet:A) encodes {"type":"scene","home":"<H>",
//   "actionSet":"<A>"} → UUID(uuidString:) restores both → identical.
// - {"v":2,"kind":"astro"} (a future shape) decodes to
//   .unknown(.object(…)) and `encode` replays that exact RuleJSONValue
//   tree — the row survives an edit-elsewhere untouched.

// MARK: - Raw JSON preservation box

/// A lossless JSON tree — the safety net under every vocabulary decode.
/// Whatever a newer client wrote is carried verbatim and re-encoded
/// verbatim; this client never destroys what it doesn't understand.
enum RuleJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: RuleJSONValue])
    case array([RuleJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([RuleJSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: RuleJSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value):   try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value):  try container.encode(value)
        case .null:              try container.encodeNil()
        }
    }

    /// Keyed access when this value is an object, nil otherwise.
    subscript(key: String) -> RuleJSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    /// Integral numbers only — a fractional hour/weekday/day count is not a
    /// well-formed shape and falls through to `.unknown` preservation.
    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(exactly: value)
    }
}

// MARK: - Condition

/// The one comparator pair v1 ships — strict less/greater than.
enum RuleComparator: String, Codable, CaseIterable, Identifiable, Sendable {
    case lt, gt
    var id: String { rawValue }

    /// "Sub" / "Peste" — the builder's segmented labels.
    var titleKey: String {
        switch self {
        case .lt: "rule_comparator_below"
        case .gt: "rule_comparator_above"
        }
    }
}

/// The weather states the cached real weather can truthfully evaluate —
/// nothing else is offered anywhere (honesty law).
enum RuleWeatherState: String, Codable, CaseIterable, Identifiable, Sendable {
    case rain, snow, frost
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .rain:  "rule_weather_rain"
        case .snow:  "rule_weather_snow"
        case .frost: "rule_weather_frost"
        }
    }

    var icon: String {
        switch self {
        case .rain:  "cloud.rain.fill"
        case .snow:  "cloud.snow.fill"
        case .frost: "snowflake"
        }
    }
}

/// The sensor half of the vocabulary — one live reading against one
/// threshold.
struct RuleSensorCondition: Equatable, Sendable {
    /// See the header: `IoTSensor.stableRef` or `IoTService.homeKitSensorId`.
    var sensorId: String
    /// Informative tag ("temperature", "humidity", an IoT SensorType raw
    /// value) — resolution is by `sensorId`; this survives for display when
    /// the sensor is temporarily absent.
    var metric: String
    var comparator: RuleComparator
    var threshold: Double
}

/// How often a schedule condition recurs.
enum RuleScheduleFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily, weekly
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .daily:  "rule_schedule_daily"
        case .weekly: "rule_schedule_weekly"
        }
    }
}

/// The schedule half of the vocabulary — a wall-clock recurrence.
struct RuleScheduleCondition: Equatable, Sendable {
    var frequency: RuleScheduleFrequency
    /// `Calendar.current` weekday numbering (1 = Sunday … 7 = Saturday in
    /// the Gregorian calendar); present ONLY for `.weekly`.
    var weekday: Int?
    var hour: Int
    var minute: Int
}

/// The geofence transition a rule can watch — mirrors
/// `HomePresenceService.Transition` raw values exactly.
enum RulePresenceEvent: String, Codable, CaseIterable, Identifiable, Sendable {
    case arrive, leave
    var id: String { rawValue }

    /// "Sosire" / "Plecare" — the builder's segmented labels.
    var titleKey: String {
        switch self {
        case .arrive: "rule_presence_arrive"
        case .leave:  "rule_presence_leave"
        }
    }
}

/// Weekday display helpers shared by the store's summaries and the builder's
/// picker — always `Calendar.current`, so names and ordering follow the
/// user's locale while the STORED number stays calendar-canonical.
enum RuleWeekday {
    /// Weekday numbers in the user's display order (starting at the
    /// locale's first weekday), each in Calendar numbering.
    static var displayOrder: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// The localized standalone name for a Calendar weekday number.
    static func name(_ weekday: Int) -> String {
        let symbols = Calendar.current.standaloneWeekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "\(weekday)" }
        return symbols[index]
    }
}

/// One rule's watched condition — the jsonb `condition` column.
enum RuleCondition: Codable, Equatable, Sendable {
    case sensor(RuleSensorCondition)
    case weather(RuleWeatherState)
    case schedule(RuleScheduleCondition)
    case docExpiry(days: Int)
    case geofence(RulePresenceEvent)
    /// A shape this app version doesn't know — preserved raw, rendered as
    /// "necunoscut", never evaluated.
    case unknown(RuleJSONValue)

    /// The current vocabulary version this client writes.
    static let version = 1

    init(from decoder: Decoder) throws {
        let raw = try RuleJSONValue(from: decoder)
        self.init(raw: raw)
    }

    /// Tolerant interpretation: anything that isn't a fully well-formed
    /// known shape becomes `.unknown(raw)` — old clients never crash on
    /// new vocabularies (and never corrupt them either).
    init(raw: RuleJSONValue) {
        switch raw["kind"]?.stringValue {
        case "sensor":
            if let sensorId = raw["sensorId"]?.stringValue,
               let metric = raw["metric"]?.stringValue,
               let comparatorRaw = raw["comparator"]?.stringValue,
               let comparator = RuleComparator(rawValue: comparatorRaw),
               let threshold = raw["threshold"]?.doubleValue {
                self = .sensor(RuleSensorCondition(sensorId: sensorId,
                                                   metric: metric,
                                                   comparator: comparator,
                                                   threshold: threshold))
                return
            }
            self = .unknown(raw)
        case "weather":
            if let stateRaw = raw["state"]?.stringValue,
               let state = RuleWeatherState(rawValue: stateRaw) {
                self = .weather(state)
                return
            }
            self = .unknown(raw)
        case "schedule":
            // Ranges are validated on decode: an out-of-range row (written
            // by a newer/looser client) is preserved, never mis-evaluated.
            if let freqRaw = raw["freq"]?.stringValue,
               let frequency = RuleScheduleFrequency(rawValue: freqRaw),
               let hour = raw["hour"]?.intValue, (0...23).contains(hour),
               let minute = raw["minute"]?.intValue, (0...59).contains(minute) {
                switch frequency {
                case .daily:
                    self = .schedule(RuleScheduleCondition(frequency: .daily,
                                                           weekday: nil,
                                                           hour: hour,
                                                           minute: minute))
                    return
                case .weekly:
                    if let weekday = raw["weekday"]?.intValue,
                       (1...7).contains(weekday) {
                        self = .schedule(RuleScheduleCondition(frequency: .weekly,
                                                               weekday: weekday,
                                                               hour: hour,
                                                               minute: minute))
                        return
                    }
                }
            }
            self = .unknown(raw)
        case "docExpiry":
            // Any non-negative horizon evaluates honestly, even beyond the
            // builder's own 1...60 offer — never destroy a wider row.
            if let days = raw["days"]?.intValue, days >= 0 {
                self = .docExpiry(days: days)
                return
            }
            self = .unknown(raw)
        case "geofence":
            if let eventRaw = raw["event"]?.stringValue,
               let event = RulePresenceEvent(rawValue: eventRaw) {
                self = .geofence(event)
                return
            }
            self = .unknown(raw)
        default:
            self = .unknown(raw)
        }
    }

    private enum SensorKeys: String, CodingKey {
        case v, kind, sensorId, metric, comparator, threshold
    }
    private enum WeatherKeys: String, CodingKey { case v, kind, state }
    private enum ScheduleKeys: String, CodingKey {
        case v, kind, freq, weekday, hour, minute
    }
    private enum DocExpiryKeys: String, CodingKey { case v, kind, days }
    private enum GeofenceKeys: String, CodingKey { case v, kind, event }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .sensor(let condition):
            var container = encoder.container(keyedBy: SensorKeys.self)
            try container.encode(Self.version, forKey: .v)
            try container.encode("sensor", forKey: .kind)
            try container.encode(condition.sensorId, forKey: .sensorId)
            try container.encode(condition.metric, forKey: .metric)
            try container.encode(condition.comparator.rawValue, forKey: .comparator)
            try container.encode(condition.threshold, forKey: .threshold)
        case .weather(let state):
            var container = encoder.container(keyedBy: WeatherKeys.self)
            try container.encode(Self.version, forKey: .v)
            try container.encode("weather", forKey: .kind)
            try container.encode(state.rawValue, forKey: .state)
        case .schedule(let condition):
            var container = encoder.container(keyedBy: ScheduleKeys.self)
            try container.encode(Self.version, forKey: .v)
            try container.encode("schedule", forKey: .kind)
            try container.encode(condition.frequency.rawValue, forKey: .freq)
            // `weekday` exists on the wire only for weekly rows.
            if condition.frequency == .weekly {
                try container.encodeIfPresent(condition.weekday, forKey: .weekday)
            }
            try container.encode(condition.hour, forKey: .hour)
            try container.encode(condition.minute, forKey: .minute)
        case .docExpiry(let days):
            var container = encoder.container(keyedBy: DocExpiryKeys.self)
            try container.encode(Self.version, forKey: .v)
            try container.encode("docExpiry", forKey: .kind)
            try container.encode(days, forKey: .days)
        case .geofence(let event):
            var container = encoder.container(keyedBy: GeofenceKeys.self)
            try container.encode(Self.version, forKey: .v)
            try container.encode("geofence", forKey: .kind)
            try container.encode(event.rawValue, forKey: .event)
        case .unknown(let raw):
            // Replay the preserved tree verbatim — never invent a shape.
            try raw.encode(to: encoder)
        }
    }
}

// MARK: - Actions

/// One entry of the jsonb `actions` array.
enum RuleAction: Codable, Equatable, Sendable {
    case notify
    case task(title: String)
    case scene(home: UUID, actionSet: UUID)
    /// Preserved raw, rendered honestly, never executed.
    case unknown(RuleJSONValue)

    init(from decoder: Decoder) throws {
        let raw = try RuleJSONValue(from: decoder)
        self.init(raw: raw)
    }

    init(raw: RuleJSONValue) {
        switch raw["type"]?.stringValue {
        case "notify":
            self = .notify
        case "task":
            if let title = raw["title"]?.stringValue {
                self = .task(title: title)
                return
            }
            self = .unknown(raw)
        case "scene":
            if let homeRaw = raw["home"]?.stringValue,
               let home = UUID(uuidString: homeRaw),
               let actionSetRaw = raw["actionSet"]?.stringValue,
               let actionSet = UUID(uuidString: actionSetRaw) {
                self = .scene(home: home, actionSet: actionSet)
                return
            }
            self = .unknown(raw)
        default:
            self = .unknown(raw)
        }
    }

    private enum Keys: String, CodingKey { case type, title, home, actionSet }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .notify:
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode("notify", forKey: .type)
        case .task(let title):
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode("task", forKey: .type)
            try container.encode(title, forKey: .title)
        case .scene(let home, let actionSet):
            var container = encoder.container(keyedBy: Keys.self)
            try container.encode("scene", forKey: .type)
            try container.encode(home.uuidString, forKey: .home)
            try container.encode(actionSet.uuidString, forKey: .actionSet)
        case .unknown(let raw):
            try raw.encode(to: encoder)
        }
    }
}

// MARK: - Row model

/// One `property_rules` row, decoded tolerantly (constitution: rows written
/// by other versions must render, never crash).
struct PropertyRule: Identifiable, Decodable, Equatable, Sendable {
    let id: UUID
    let propertyId: UUID
    var name: String
    var enabled: Bool
    var condition: RuleCondition
    var actions: [RuleAction]
    var cooldownMinutes: Int
    var lastFiredAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, condition, actions
        case propertyId      = "property_id"
        case cooldownMinutes = "cooldown_minutes"
        case lastFiredAt     = "last_fired_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(UUID.self, forKey: .id)
        propertyId      = try c.decode(UUID.self, forKey: .propertyId)
        name            = try c.decode(String.self, forKey: .name)
        enabled         = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        condition       = (try? c.decode(RuleCondition.self, forKey: .condition))
                          ?? .unknown(.null)
        actions         = (try? c.decode([RuleAction].self, forKey: .actions)) ?? []
        cooldownMinutes = (try? c.decode(Int.self, forKey: .cooldownMinutes)) ?? 60
        lastFiredAt     = try? c.decodeIfPresent(Date.self, forKey: .lastFiredAt)
    }

    /// Whether the builder can faithfully re-open this rule: every stored
    /// shape must be understood, otherwise editing would silently destroy a
    /// newer client's data — the row stays toggle/delete-only instead.
    var isEditable: Bool {
        if case .unknown = condition { return false }
        for action in actions {
            if case .unknown = action { return false }
        }
        return true
    }
}

/// INSERT payload — `created_by`, timestamps and `id` come from column
/// defaults; the jsonb columns encode straight from the vocabulary types.
struct NewPropertyRuleRow: Encodable, Sendable {
    let propertyId: UUID
    let name: String
    let enabled: Bool
    let condition: RuleCondition
    let actions: [RuleAction]
    let cooldownMinutes: Int

    enum CodingKeys: String, CodingKey {
        case name, enabled, condition, actions
        case propertyId      = "property_id"
        case cooldownMinutes = "cooldown_minutes"
    }
}

/// Builder-edit PATCH — the full editable surface in one write.
struct PropertyRuleUpdate: Encodable, Sendable {
    let name: String
    let condition: RuleCondition
    let actions: [RuleAction]
    let cooldownMinutes: Int
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case name, condition, actions
        case cooldownMinutes = "cooldown_minutes"
        case updatedAt       = "updated_at"
    }
}

// MARK: - Cooldown options

/// The cooldowns the builder offers. Raw value = minutes (the column's
/// unit); rows written with any other minute count still work — the picker
/// just snaps to the nearest option when such a rule is edited.
enum RuleCooldown: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case oneHour        = 60
    case sixHours       = 360
    case day            = 1440

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .fifteenMinutes: "rule_cooldown_15m"
        case .oneHour:        "rule_cooldown_1h"
        case .sixHours:       "rule_cooldown_6h"
        case .day:            "rule_cooldown_24h"
        }
    }

    /// The option nearest to an arbitrary stored minute count.
    static func nearest(to minutes: Int) -> RuleCooldown {
        allCases.min { abs($0.rawValue - minutes) < abs($1.rawValue - minutes) } ?? .oneHour
    }
}

// MARK: - Live sensor universe

/// One pickable/resolvable live reading — the union the engine and the
/// builder share: IoT hub sensors currently reporting a fresh numeric value
/// ∪ the HomeKit indoor-climate readings cached by `IndoorClimateStore`
/// (each up to two metrics). Only REAL current values ever appear here.
struct RuleSensorOption: Identifiable, Equatable, Sendable {
    /// The vocabulary `sensorId` (stableRef or hk:… — see the header).
    let id: String
    let name: String
    /// Zone/room attribution when the sensor carries one.
    let zone: String?
    let metric: String
    let unit: String
    let value: Double

    /// "21,5 °C" — locale-aware, at most one decimal, the app's style.
    var valueText: String { RuleValueText.text(value, unit: unit) }

    /// "Living · Termostat · 21,5 °C" — the picker's one-line label.
    var pickerLabel: String {
        var parts: [String] = []
        if let zone, !zone.isEmpty { parts.append(zone) }
        parts.append(name)
        parts.append(valueText)
        return parts.joined(separator: " · ")
    }
}

/// Shared value formatting for thresholds, live readings and log lines.
enum RuleValueText {
    static func text(_ value: Double, unit: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0...1)))
        guard !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }
}

// MARK: - Firing log

/// What one action did when its rule fired — raw tokens persisted in the
/// local ring buffer, localized at render (tolerant of tokens from newer
/// versions via `.unknown`).
enum RuleActionOutcome: String, Codable, Sendable {
    case notified, notifyDenied, notifyOff, notifyFailed
    case taskCreated, taskDuplicate, taskFailed
    case sceneRun, sceneFailed, sceneMissing
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RuleActionOutcome(rawValue: raw) ?? .unknown
    }

    var titleKey: String? {
        switch self {
        case .notified:      "rule_outcome_notified"
        case .notifyDenied:  "rule_outcome_notify_denied"
        case .notifyOff:     "rule_outcome_notify_off"
        case .notifyFailed:  "rule_outcome_notify_failed"
        case .taskCreated:   "rule_outcome_task_created"
        case .taskDuplicate: "rule_outcome_task_duplicate"
        case .taskFailed:    "rule_outcome_task_failed"
        case .sceneRun:      "rule_outcome_scene_run"
        case .sceneFailed:   "rule_outcome_scene_failed"
        case .sceneMissing:  "rule_outcome_scene_missing"
        case .unknown:       nil
        }
    }
}

/// One firing, as the "Istoric declanșări" section shows it — kept in a
/// small local ring buffer (UserDefaults, newest first, last 50).
struct RuleFiringRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let ruleId: UUID
    let ruleName: String
    let firedAt: Date
    /// The composed live-value line (the notification body's text).
    let detail: String
    let outcomes: [RuleActionOutcome]
}
