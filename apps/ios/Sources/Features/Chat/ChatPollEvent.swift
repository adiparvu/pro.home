import SwiftUI
import EventKit

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
    let date: String   // ISO8601
    let loc: String?

    static func decode(_ body: String?) -> ChatEvent? {
        guard let data = body?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ChatEvent.self, from: data)
    }
    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    var parsedDate: Date? { ISODate.date(from: date) }
    var dateDisplay: String {
        guard let d = parsedDate else { return date }
        let out = DateFormatter(); out.dateFormat = "EEE, d MMM • HH:mm"; out.locale = .current
        return out.string(from: d)
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
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Event bubble

struct EventBubble: View {
    let event: ChatEvent
    let isOwn: Bool
    var bubbleColor: Color = Color.blue.opacity(0.75)

    /// Readable foreground over the themed bubble fill.
    private var onBubble: Color { bubbleColor.readableText }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(AppFont.scaled(12))
                Text("Event").font(AppFont.label)
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

            Label(event.dateDisplay, systemImage: "clock")
                .font(AppFont.scaled(12))
                .foregroundStyle(isOwn ? onBubble.opacity(0.85) : Color.primary.opacity(0.6))

            if let loc = event.loc, !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(isOwn ? onBubble.opacity(0.85) : Color.primary.opacity(0.6))
                    .lineLimit(1)
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
        }
        .padding(AppSpacing.base)
        .frame(maxWidth: 260, alignment: .leading)
        .background(isOwn ? bubbleColor : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            ek.startDate = start
            ek.endDate = start.addingTimeInterval(3600)
            ek.notes = event.d
            ek.location = event.loc
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
        .presentationBackground(.thinMaterial)
    }
}

// MARK: - Event composer

struct EventComposerView: View {
    let onSend: (String, String, Date, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var details = ""
    @State private var date = Date()
    @State private var location = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                Form {
                    Section {
                        TextField("Add the event name", text: $title)
                        TextField("Add a description (optional)", text: $details, axis: .vertical)
                    }
                    Section {
                        DatePicker("Starts", selection: $date)
                    }
                    Section {
                        TextField("Add the location (optional)", text: $location)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Create an event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSend(title.trimmingCharacters(in: .whitespaces), details.trimmingCharacters(in: .whitespaces), date, location.trimmingCharacters(in: .whitespaces))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationBackground(.thinMaterial)
    }
}
