import SwiftUI
import EventKit
import CoreLocation

// MARK: - Payloads (stored as JSON in message.body; attachment_type = "poll" | "event")

struct ChatPoll: Codable {
    let q: String
    let opts: [String]
    let multi: Bool

    static func decode(_ body: String?) -> ChatPoll? {
        guard let data = body?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatPoll.self, from: data)
    }
    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct ChatEvent: Codable {
    let t: String
    let d: String?
    let date: String   // ISO8601 start
    let loc: String?
    /// ISO8601 end — absent on pre-upgrade payloads, which render as a
    /// single start moment exactly like before.
    var end: String? = nil
    /// All-day flag — absent (nil) on pre-upgrade payloads ⇒ timed event.
    var allDay: Bool? = nil
    /// Coordinates of the picked map location (v3) — present only when the
    /// composer's location came from a real Apple Maps pick, absent on older
    /// payloads and on free-text locations. Encoded only when non-nil (the
    /// same discipline as end/allDay), so old clients see the exact old
    /// shape and old bodies decode with nil here.
    var lat: Double? = nil
    var lon: Double? = nil

    static func decode(_ body: String?) -> ChatEvent? {
        guard let data = body?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatEvent.self, from: data)
    }
    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    var parsedDate: Date? { ISODate.date(from: date) }
    var parsedEnd: Date? { end.flatMap { ISODate.date(from: $0) } }
    var isAllDay: Bool { allDay ?? false }

    // Cached formatters — bubbles re-render on every scroll pass and
    // DateFormatter construction is expensive. Localized templates follow
    // the user's region (incl. 12/24-hour preference).
    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return f
    }()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()

    /// The bubble's formatted, all-day-aware date range. Legacy payloads
    /// (no `end`) keep their historical "day • time" rendering.
    var scheduleDisplay: String {
        guard let start = parsedDate else { return date }
        let cal = Calendar.current
        let day = Self.dayFmt.string(from: start)
        if isAllDay {
            if let e = parsedEnd, !cal.isDate(start, inSameDayAs: e) {
                return "\(day) – \(Self.dayFmt.string(from: e))"
            }
            return day
        }
        let t1 = Self.timeFmt.string(from: start)
        guard let e = parsedEnd, e > start else { return "\(day) • \(t1)" }
        let t2 = Self.timeFmt.string(from: e)
        if cal.isDate(start, inSameDayAs: e) {
            return "\(day) • \(t1)–\(t2)"
        }
        return "\(day), \(t1) – \(Self.dayFmt.string(from: e)), \(t2)"
    }
}

// MARK: - Event draft (composer → sender)

/// Everything the composer collected. `payload()` is the single wire encoder
/// for both engines (group JSON body and DM marker body), so the two send
/// paths can never drift.
struct ChatEventDraft {
    let title: String
    let details: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String
    /// Coordinates of the picked map location — nil for free-text locations.
    var lat: Double? = nil
    var lon: Double? = nil

    /// The wire payload. All-day dates normalize to local start-of-day; the
    /// end never precedes the start. Coordinates only ever ride alongside a
    /// non-empty location text — a pin with no visible name would be
    /// unverifiable by the reader.
    func payload() -> ChatEvent {
        let cal = Calendar.current
        let s = isAllDay ? cal.startOfDay(for: start) : start
        let e = max(isAllDay ? cal.startOfDay(for: end) : end, s)
        return ChatEvent(
            t: title,
            d: details.isEmpty ? nil : details,
            date: ISODate.string(from: s),
            loc: location.isEmpty ? nil : location,
            end: ISODate.string(from: e),
            allDay: isAllDay ? true : nil,
            lat: location.isEmpty ? nil : lat,
            lon: location.isEmpty ? nil : lon)
    }
}

// MARK: - Poll vote model

struct PollVote: Identifiable, Codable {
    let id: UUID
    let messageId: UUID
    let userId: UUID?
    let voterName: String
    let optionIndex: Int

    enum CodingKeys: String, CodingKey {
        case id
        case messageId   = "message_id"
        case userId      = "user_id"
        case voterName   = "voter_name"
        case optionIndex = "option_index"
    }
}

// MARK: - Poll tally (pure, testable)

enum PollTally {
    /// Stable per-voter identity. Falls back to the voter name when there is no
    /// user id, so multiple anonymous/guest voters are not collapsed into one.
    static func voterKey(_ v: PollVote) -> String {
        if let id = v.userId { return "id:\(id.uuidString)" }
        return "name:\(v.voterName)"
    }
    static func totalVoters(_ votes: [PollVote]) -> Int {
        Set(votes.map(voterKey)).count
    }
    /// Distinct voters who picked this option (deduped against repeated votes).
    static func count(_ votes: [PollVote], option: Int) -> Int {
        Set(votes.filter { $0.optionIndex == option }.map(voterKey)).count
    }
    static func didVote(_ votes: [PollVote], option: Int, userId: UUID?) -> Bool {
        // Without a resolved identity we cannot claim the current user voted.
        guard let userId else { return false }
        return votes.contains { $0.optionIndex == option && $0.userId == userId }
    }
    static func fraction(_ votes: [PollVote], option: Int) -> Double {
        let total = totalVoters(votes)
        return total > 0 ? Double(count(votes, option: option)) / Double(total) : 0
    }
}

// MARK: - Poll bubble

struct PollBubble: View {
    let poll: ChatPoll
    let votes: [PollVote]
    let myUserId: UUID?
    let isOwn: Bool
    var bubbleColor: Color = Color.blue.opacity(0.75)
    let onVote: (Int) -> Void

    /// Readable foreground over the themed bubble fill.
    private var onBubble: Color { bubbleColor.readableText }

    @State private var showVotes = false

    private var totalVoters: Int { PollTally.totalVoters(votes) }
    private func count(_ i: Int) -> Int { PollTally.count(votes, option: i) }
    private func didVote(_ i: Int) -> Bool { PollTally.didVote(votes, option: i, userId: myUserId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill").font(AppFont.scaled(12))
                Text(poll.multi ? "Selectează una sau mai multe" : "Selectează una")
                    .font(AppFont.label)
            }
            .foregroundStyle(isOwn ? onBubble.opacity(0.85) : Color.accentColor)

            Text(poll.q)
                .font(AppFont.subheadline)
                .foregroundStyle(isOwn ? onBubble : .primary)

            VStack(spacing: 8) {
                ForEach(Array(poll.opts.enumerated()), id: \.offset) { i, opt in
                    Button { onVote(i) } label: { optionRow(i, opt) }
                        .buttonStyle(.plain)
                }
            }

            Text(totalVoters == 1 ? "1 vot" : "\(totalVoters) voturi")
                .font(AppFont.scaled(11))
                .foregroundStyle(isOwn ? onBubble.opacity(0.7) : Color.primary.opacity(AppOpacity.secondaryText))

            Divider().overlay(isOwn ? onBubble.opacity(0.25) : Color.primary.opacity(0.12))

            Button { showVotes = true } label: {
                Text("Afișează voturile")
                    .font(AppFont.footnote)
                    .foregroundStyle(isOwn ? onBubble : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .disabled(totalVoters == 0)
            .opacity(totalVoters == 0 ? 0.45 : 1)
        }
        .padding(AppSpacing.base)
        .frame(maxWidth: 260, alignment: .leading)
        .background(isOwn ? bubbleColor : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sheet(isPresented: $showVotes) {
            PollVotesSheet(poll: poll, votes: votes)
        }
    }

    private func optionRow(_ i: Int, _ opt: String) -> some View {
        let c = count(i)
        let frac = totalVoters > 0 ? Double(c) / Double(totalVoters) : 0
        let mine = didVote(i)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: mine ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(mine ? (isOwn ? onBubble : Color.accentColor) : (isOwn ? onBubble.opacity(0.6) : Color.primary.opacity(0.4)))
                Text(opt)
                    .font(AppFont.scaled(14))
                    .foregroundStyle(isOwn ? onBubble : .primary)
                Spacer()
                Text("\(c)")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(isOwn ? onBubble.opacity(0.8) : Color.primary.opacity(AppOpacity.mediumText))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(isOwn ? onBubble.opacity(0.2) : Color.primary.opacity(0.1))
                    Capsule().fill(isOwn ? onBubble.opacity(0.55) : Color.accentColor.opacity(0.5))
                        .frame(width: max(4, geo.size.width * frac))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Poll votes sheet

struct PollVotesSheet: View {
    let poll: ChatPoll
    let votes: [PollVote]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                List {
                    ForEach(Array(poll.opts.enumerated()), id: \.offset) { i, opt in
                        let voters = votes.filter { $0.optionIndex == i }
                        Section("\(opt) · \(voters.count)") {
                            if voters.isEmpty {
                                Text("Niciun vot")
                                    .foregroundStyle(Color.primary.opacity(0.4))
                            } else {
                                ForEach(voters) { v in
                                    Text(v.voterName.isEmpty ? "Membru" : v.voterName)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Voturi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .sheetGround()
    }
}

// MARK: - Event bubble

struct EventBubble: View {
    let event: ChatEvent
    let isOwn: Bool
    var bubbleColor: Color = Color.blue.opacity(0.75)
    /// RSVP responses, stored through the poll-vote infrastructure
    /// (option 0 = going, option 1 = can't go).
    var votes: [PollVote] = []
    var myUserId: UUID? = nil
    /// Provided only where RSVP storage exists (`message_poll_votes` for
    /// group chat, `dm_poll_votes` via DMVoteStore for DM threads); nil
    /// hides the buttons entirely.
    var onRSVP: ((Int) -> Void)? = nil

    /// Readable foreground over the themed bubble fill.
    private var onBubble: Color { bubbleColor.readableText }

    static let rsvpGoing = 0
    static let rsvpDeclined = 1

    /// Navigation-app chooser for a location that carries real coordinates.
    @State private var showNavigationChooser = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(AppFont.scaled(12))
                Text("ev_bubble_kind").font(AppFont.label)
            }
            .foregroundStyle(isOwn ? onBubble.opacity(0.85) : Color.red)

            Text(event.t)
                .font(AppFont.subheadline)
                .foregroundStyle(isOwn ? onBubble : .primary)

            if let d = event.d, !d.isEmpty {
                Text(d).font(AppFont.scaled(13))
                    .foregroundStyle(isOwn ? onBubble.opacity(0.85) : Color.primary.opacity(AppOpacity.emphasis))
                    .lineLimit(3)
            }

            Label(scheduleText, systemImage: "calendar")
                .font(AppFont.scaled(12))
                .foregroundStyle(isOwn ? onBubble.opacity(0.85) : Color.primary.opacity(0.6))

            if let loc = event.loc, !loc.isEmpty {
                if let lat = event.lat, let lon = event.lon {
                    // A real map pin travelled with the payload — the line is
                    // tappable and hands off to the reader's navigation app
                    // (same chooser as shared locations). Text-only locations
                    // stay plain: no coordinates, no pretend map link.
                    Button {
                        HapticFeedback.impact(.light)
                        showNavigationChooser = true
                    } label: {
                        HStack(spacing: AppSpacing.xxs) {
                            Label(loc, systemImage: "mappin.and.ellipse")
                                .lineLimit(1)
                            Image(systemName: "map")
                                .font(AppFont.scaled(11, weight: .semibold))
                        }
                        .font(AppFont.scaled(12))
                        .foregroundStyle(isOwn ? onBubble.opacity(0.85) : Color.accentColor)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("ev_open_in_maps"))
                    .confirmationDialog(loc, isPresented: $showNavigationChooser,
                                        titleVisibility: .visible) {
                        ForEach(NavigationAppLauncher.availableOptions()) { opt in
                            Button(opt.label) {
                                NavigationAppLauncher.open(opt.id, lat: lat, lon: lon, label: loc)
                            }
                        }
                    }
                } else {
                    Label(loc, systemImage: "mappin.and.ellipse")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(isOwn ? onBubble.opacity(0.85) : Color.primary.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Button { addToCalendar() } label: {
                Text("Add to Calendar")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(isOwn ? onBubble : Color.accentColor)
                    .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xs)
                    .background((isOwn ? onBubble.opacity(0.2) : Color.accentColor.opacity(0.12)), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            if let onRSVP {
                Divider().overlay(isOwn ? onBubble.opacity(0.25) : Color.primary.opacity(0.12))

                HStack(spacing: AppSpacing.sm) {
                    rsvpChip(option: Self.rsvpGoing, title: "ev_rsvp_yes",
                             icon: "checkmark.circle", accent: isOwn ? onBubble : .brandSuccess,
                             action: onRSVP)
                    rsvpChip(option: Self.rsvpDeclined, title: "ev_rsvp_no",
                             icon: "xmark.circle",
                             accent: isOwn ? onBubble.opacity(0.85) : Color.primary.opacity(AppOpacity.emphasis),
                             action: onRSVP)
                }

                let going = PollTally.count(votes, option: Self.rsvpGoing)
                if going > 0 {
                    // RO "participă" is invariant across counts, so a plain
                    // format string stays grammatical for 1 and many.
                    Text(String(format: String(localized: "ev_rsvp_going_fmt"), going))
                        .font(AppFont.scaled(11))
                        .foregroundStyle(isOwn ? onBubble.opacity(0.7) : Color.primary.opacity(AppOpacity.secondaryText))
                }
            }
        }
        .padding(AppSpacing.base)
        .frame(maxWidth: 260, alignment: .leading)
        .background(isOwn ? bubbleColor : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var scheduleText: String {
        event.isAllDay
            ? "\(event.scheduleDisplay) · \(String(localized: "ev_all_day"))"
            : event.scheduleDisplay
    }

    /// One RSVP capsule: my choice fills and strokes in the accent, the
    /// count rides inside so tallies are always live.
    private func rsvpChip(option: Int, title: LocalizedStringKey, icon: String,
                          accent: Color, action: @escaping (Int) -> Void) -> some View {
        let count = PollTally.count(votes, option: option)
        let mine = PollTally.didVote(votes, option: option, userId: myUserId)
        return Button {
            HapticFeedback.impact(.light)
            action(option)
        } label: {
            HStack(spacing: AppSpacing.xxs) {
                Image(systemName: mine ? icon + ".fill" : icon)
                    .font(AppFont.scaled(13))
                Text(title)
                    .font(AppFont.captionStrong)
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .font(AppFont.captionStrong)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xs)
            .background(accent.opacity(mine ? 0.22 : (isOwn ? 0.10 : AppOpacity.subtleFill)),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(accent.opacity(mine ? 0.5 : 0), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mine ? .isSelected : [])
    }

    private func addToCalendar() {
        guard let start = event.parsedDate else { HapticFeedback.warning(); return }
        let store = EKEventStore()
        // Full access so we can resolve a writable calendar (write-only access
        // hides defaultCalendarForNewEvents, which is why saving used to fail).
        store.requestFullAccessToEvents { granted, _ in
            guard granted else { DispatchQueue.main.async { HapticFeedback.warning() }; return }
            let calendar = store.defaultCalendarForNewEvents
                ?? store.calendars(for: .event).first(where: { $0.allowsContentModifications })
            guard let calendar else { DispatchQueue.main.async { HapticFeedback.warning() }; return }
            let ek = EKEvent(eventStore: store)
            ek.title = event.t
            if event.isAllDay {
                ek.isAllDay = true
                ek.startDate = start
                ek.endDate = event.parsedEnd.map { max($0, start) } ?? start
            } else {
                ek.startDate = start
                ek.endDate = event.parsedEnd.map { max($0, start) } ?? start.addingTimeInterval(3600)
            }
            ek.notes = event.d
            // location first: assigning it resets any structuredLocation to a
            // title-only one, so the geocoded pin must be applied after it.
            ek.location = event.loc
            if let lat = event.lat, let lon = event.lon {
                // The composer's map pin — a structured location makes Apple
                // Calendar render the map preview and enables travel-time.
                let place = EKStructuredLocation(title: event.loc ?? event.t)
                place.geoLocation = CLLocation(latitude: lat, longitude: lon)
                ek.structuredLocation = place
            }
            ek.calendar = calendar
            do {
                try store.save(ek, span: .thisEvent)
                DispatchQueue.main.async { HapticFeedback.success() }
            } catch {
                DispatchQueue.main.async { HapticFeedback.warning() }
            }
        }
    }
}

// MARK: - Poll composer

struct PollComposerView: View {
    let onSend: (String, [String], Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var options: [String] = ["", ""]
    @State private var multi = false

    private var canSend: Bool {
        !question.trimmingCharacters(in: .whitespaces).isEmpty &&
        options.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count >= 2
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                Form {
                    Section("Question") {
                        TextField("Write the question", text: $question, axis: .vertical)
                    }
                    Section("Options") {
                        ForEach(options.indices, id: \.self) { i in
                            TextField("Add", text: $options[i])
                        }
                        Button { options.append("") } label: {
                            Label("Add option", systemImage: "plus.circle")
                        }
                        .disabled(options.count >= 12)
                    }
                    Section {
                        Toggle("Allow multiple answers", isOn: $multi)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Create a poll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        let opts = options.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        onSend(question.trimmingCharacters(in: .whitespaces), opts, multi)
                        dismiss()
                    }
                    .disabled(!canSend)
                }
            }
        }
        .sheetGround()
    }
}

// MARK: - Event composer

struct EventComposerView: View {
    let onSend: (ChatEventDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var allDay = false
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var location = ""
    /// Coordinates from the last real map pick, kept only while the visible
    /// text still names that pin (see the onChange below). `pickedName`
    /// remembers what the pin was called so a manual edit is detectable.
    @State private var pickedLat: Double? = nil
    @State private var pickedLon: Double? = nil
    @State private var pickedName: String? = nil
    @State private var addToAppleCalendar = false
    @State private var showLocationPicker = false

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (allDay || end >= start)
    }

    /// Bridges the location to the shared Apple Maps search picker (the tasks
    /// form's). A resolved pick flows back with its coordinates; free-text
    /// picks stay text-only — coordinates are never invented.
    private var pickedLocation: Binding<TaskLocationValue?> {
        Binding(
            get: {
                let t = location.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : TaskLocationValue(name: t, lat: pickedLat, lon: pickedLon)
            },
            set: {
                location = $0?.name ?? ""
                pickedLat = $0?.lat
                pickedLon = $0?.lon
                // Only a coordinate-bearing pick is worth remembering — the
                // name is what a later manual edit is compared against.
                pickedName = ($0?.lat != nil)
                    ? $0?.name.trimmingCharacters(in: .whitespaces) : nil
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                Form {
                    Section {
                        TextField("Add the event name", text: $title)
                        TextField("Add a description (optional)", text: $details, axis: .vertical)
                            .lineLimit(1...4)
                    } header: {
                        Label("ev_section_details", systemImage: "square.and.pencil")
                    }

                    Section {
                        Toggle("ev_all_day", isOn: $allDay.animation(.snappy(duration: 0.25)))
                        DatePicker("Starts", selection: $start,
                                   displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                        DatePicker("ev_ends", selection: $end, in: start...,
                                   displayedComponents: allDay ? [.date] : [.date, .hourAndMinute])
                    } header: {
                        Label("ev_section_schedule", systemImage: "clock")
                    }

                    Section {
                        HStack(spacing: AppSpacing.sm) {
                            TextField("Add the location (optional)", text: $location)
                            Button {
                                HapticFeedback.impact(.light)
                                showLocationPicker = true
                            } label: {
                                Image(systemName: "mappin.circle.fill")
                                    .font(AppFont.scaled(20))
                                    .foregroundStyle(Color.brandPurple)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("ev_location_search"))
                        }
                    } header: {
                        Label("ev_section_location", systemImage: "mappin.and.ellipse")
                    }

                    Section {
                        Toggle("ev_add_apple_cal", isOn: $addToAppleCalendar)
                    } footer: {
                        Text("ev_add_apple_cal_footer")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(Text("ev_new_title"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: start) { old, new in
                // Apple Calendar behavior: moving the start slides the end to
                // preserve the chosen duration (and end can never precede start).
                end = max(end.addingTimeInterval(new.timeIntervalSince(old)), new)
            }
            .onChange(of: location) { _, new in
                // Honesty: a manually edited location no longer names the
                // picked pin, so the stale coordinates must not ride along.
                // (The picker's own set writes the matching name, so it never
                // trips this.)
                guard let name = pickedName,
                      new.trimmingCharacters(in: .whitespaces) != name else { return }
                pickedLat = nil
                pickedLon = nil
                pickedName = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(!canSend)
                }
            }
            .sheet(isPresented: $showLocationPicker) {
                TaskLocationPickerSheet(location: pickedLocation)
            }
        }
        .sheetGround()
    }

    private func send() {
        let draft = ChatEventDraft(
            title: title.trimmingCharacters(in: .whitespaces),
            details: details.trimmingCharacters(in: .whitespaces),
            start: start, end: max(end, start), isAllDay: allDay,
            location: location.trimmingCharacters(in: .whitespaces),
            lat: pickedLat, lon: pickedLon)
        onSend(draft)
        if addToAppleCalendar {
            // Device-local Apple Calendar write — independent of the message
            // send, so it survives this sheet's dismissal.
            Task { @MainActor in
                let ok = await HouseCalendarMirror.addChatEvent(
                    title: draft.title,
                    notes: draft.details.isEmpty ? nil : draft.details,
                    location: draft.location.isEmpty ? nil : draft.location,
                    lat: draft.location.isEmpty ? nil : draft.lat,
                    lon: draft.location.isEmpty ? nil : draft.lon,
                    start: draft.start, end: draft.end, isAllDay: draft.isAllDay)
                if !ok { HapticFeedback.warning() }
            }
        }
        dismiss()
    }
}
