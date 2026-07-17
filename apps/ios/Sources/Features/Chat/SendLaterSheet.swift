import SwiftUI

// MARK: - Send Later (scheduled messages)
//
// Compose-and-schedule sheet for the group chat and DM threads. The app only
// does CRUD on `scheduled_messages` — a server-side cron job delivers due
// rows every minute, so nothing here depends on the app being alive at send
// time. One sheet serves both conversation kinds via SendLaterContext.
//
// The sheet exposes exactly what the backend supports:
// - repeat_rule ∈ {once, daily, weekly, monthly} — mirrors the DB check
//   constraint and the pg_cron step logic in migration 110; never invent
//   values outside this set.
// - repeat_until — optional recurrence end, honored by the cron worker.
// - Editing: the service has no update API (schedule + cancel only), so
//   "edit" prefills the form and replaces the row on save (create new,
//   then cancel the old one).

enum SendLaterContext {
    case group(propertyId: UUID, authorId: UUID, authorName: String)
    case dm(propertyId: UUID?, authorId: UUID, authorName: String, recipientName: String)
}

// MARK: - Repeat cadence (backend-defined vocabulary)

/// The four cadences `scheduled_messages.repeat_rule` accepts —
/// `check (repeat_rule in ('once','daily','weekly','monthly'))`.
private enum SendLaterRepeat: String, CaseIterable, Identifiable {
    case once, daily, weekly, monthly

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .once:    return "Once"
        case .daily:   return "Daily"
        case .weekly:  return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

// MARK: - Quick time picks

/// The three one-tap send times. Each recomputes its target from `now` so a
/// chip can never schedule into the past: "tonight" simply disappears once
/// 20:00 has gone by.
private enum SendLaterQuickPick: String, CaseIterable, Identifiable {
    case inOneHour, tonight, tomorrowMorning

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inOneHour:       return "clock"
        case .tonight:         return "moon.stars"
        case .tomorrowMorning: return "sunrise"
        }
    }

    /// Next 5-minute mark at least `interval` from now — a tidy default that
    /// never lands in the past.
    static func roundedUp(_ date: Date) -> Date {
        let step: TimeInterval = 5 * 60
        let rounded = (date.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    /// The concrete send time this chip stands for, or nil when that moment
    /// has already passed today (never offer a past time).
    func target(now: Date) -> Date? {
        let cal = Calendar.current
        switch self {
        case .inOneHour:
            return Self.roundedUp(now.addingTimeInterval(3600))
        case .tonight:
            guard let tonight = cal.date(bySettingHour: 20, minute: 0, second: 0, of: now),
                  tonight > now else { return nil }
            return tonight
        case .tomorrowMorning:
            guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }

    /// Localized chip title; times render through the user's locale
    /// ("20:00" / "8:00 PM"), never hardcoded.
    func title(now: Date) -> String {
        switch self {
        case .inOneHour:
            return String(localized: "sl_chip_in_1h")
        case .tonight:
            let time = (target(now: now) ?? now).formatted(date: .omitted, time: .shortened)
            return String(localized: "sl_chip_tonight \(time)")
        case .tomorrowMorning:
            let time = (target(now: now) ?? now).formatted(date: .omitted, time: .shortened)
            return String(localized: "sl_chip_tomorrow \(time)")
        }
    }

    static func available(now: Date) -> [SendLaterQuickPick] {
        allCases.filter { $0.target(now: now) != nil }
    }
}

// MARK: - Sheet

struct SendLaterSheet: View {
    let context: SendLaterContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var service = ScheduledMessageService()

    @State private var messageBody = ""
    @State private var sendAt: Date
    @State private var repeatRule: SendLaterRepeat = .once
    @State private var hasEndDate = false
    @State private var repeatUntil: Date

    @State private var activeChip: SendLaterQuickPick?
    @State private var chipAppliedDate: Date?

    /// Row being edited. The service only supports schedule + cancel, so
    /// saving while editing replaces the row (create new, cancel old).
    @State private var editingItem: ScheduledMessage?

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(context: SendLaterContext) {
        self.context = context
        let firstSend = SendLaterQuickPick.roundedUp(Date().addingTimeInterval(3600))
        _sendAt = State(initialValue: firstSend)
        _repeatUntil = State(initialValue: Calendar.current.date(
            byAdding: .month, value: 1, to: firstSend) ?? firstSend)
    }

    // MARK: - Context accessors

    private var propertyId: UUID? {
        switch context {
        case .group(let pid, _, _): return pid
        case .dm(let pid, _, _, _): return pid
        }
    }
    private var authorId: UUID {
        switch context {
        case .group(_, let aid, _): return aid
        case .dm(_, let aid, _, _): return aid
        }
    }
    private var authorName: String {
        switch context {
        case .group(_, _, let name): return name
        case .dm(_, _, let name, _): return name
        }
    }
    private var target: String {
        if case .group = context { return "group" }
        return "dm"
    }
    private var dmRecipient: String? {
        if case .dm(_, _, _, let recipient) = context { return recipient }
        return nil
    }

    // MARK: - Validation

    private var trimmedBody: String {
        messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool {
        propertyId != nil && !trimmedBody.isEmpty && !isSaving
    }
    /// The recurrence end actually sent to the backend: end of the chosen
    /// day, so "until Aug 12" includes Aug 12's send — and only when the
    /// schedule repeats.
    private var scheduledRepeatUntil: Date? {
        guard repeatRule != .once, hasEndDate else { return nil }
        return Calendar.current.date(bySettingHour: 23, minute: 59, second: 0,
                                     of: repeatUntil) ?? repeatUntil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: AppSpacing.xl) {
                            if editingItem != nil {
                                editingBanner
                            }
                            messageCard
                                .id("composeTop")
                            timingSection
                            repeatSection
                            saveArea
                            if propertyId == nil {
                                Text("Set up your property first.")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.secondaryTextColor)
                            }
                            scheduledSection
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, AppSpacing.xl)
                        .padding(.top, AppSpacing.sm)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: editingItem?.id) { _, new in
                        guard new != nil else { return }
                        if reduceMotion {
                            proxy.scrollTo("composeTop", anchor: .top)
                        } else {
                            withAnimation(.smooth) { proxy.scrollTo("composeTop", anchor: .top) }
                        }
                    }
                }
            }
            .navigationTitle(Text("Send Later"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
            }
            .alert("Couldn't schedule the message", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                guard let pid = propertyId else { return }
                await service.load(propertyId: pid, target: target, dmRecipient: dmRecipient)
            }
            .onChange(of: sendAt) { _, new in
                // Manual picker edits release the quick chip; the chip only
                // stays lit while the pickers still show exactly its time.
                if new != chipAppliedDate {
                    activeChip = nil
                    chipAppliedDate = nil
                }
                if repeatUntil < new { repeatUntil = new }
            }
        }
        .presentationBackground(.thinMaterial)
    }

    // MARK: - Compose

    private var messageCard: some View {
        card {
            TextField("Message…", text: $messageBody, axis: .vertical)
                .lineLimit(3...6)
                .font(AppFont.body)
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
        }
    }

    private var editingBanner: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "pencil.circle.fill")
                .font(AppFont.headline)
                .foregroundStyle(Color.accentColor)
            Text("sl_editing")
                .font(AppFont.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: AppSpacing.sm)
            Button {
                HapticFeedback.impact(.light)
                cancelEditing()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.headline)
                    .foregroundStyle(Color.secondaryTextColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("sl_cancel_edit"))
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .liquidGlass(cornerRadius: AppRadius.lg)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Timing

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(icon: "clock", title: "Send at")
            quickChips
            card {
                DatePicker(selection: $sendAt, in: Date()...,
                           displayedComponents: [.date, .hourAndMinute]) {
                    Label("sl_date_time", systemImage: "calendar")
                        .font(AppFont.subheadline).foregroundStyle(.primary)
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
            }
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.sm) {
                ForEach(SendLaterQuickPick.available(now: Date())) { chip in
                    GlassFilterChip(label: chip.title(now: Date()),
                                    systemImage: chip.icon,
                                    isSelected: activeChip == chip) {
                        applyChip(chip)
                    }
                }
            }
            .padding(.vertical, AppSpacing.xxs)
        }
    }

    private func applyChip(_ chip: SendLaterQuickPick) {
        // Recompute at tap time — a chip rendered a while ago must still
        // never set a time that has meanwhile slipped into the past.
        guard let target = chip.target(now: Date()), target > Date() else { return }
        activeChip = chip
        chipAppliedDate = target
        if reduceMotion {
            sendAt = target
        } else {
            withAnimation(AppMotion.state) { sendAt = target }
        }
    }

    // MARK: - Recurrence

    private var repeatSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(icon: "calendar.badge.clock", title: "sl_repeat")
            card {
                repeatRuleRow
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.md)
                if repeatRule != .once {
                    Divider().overlay(Color.hairline)
                    Toggle(isOn: $hasEndDate) {
                        Label("Until", systemImage: "calendar")
                            .font(AppFont.subheadline).foregroundStyle(.primary)
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.sm)
                    if hasEndDate {
                        Divider().overlay(Color.hairline)
                        HStack {
                            Spacer(minLength: AppSpacing.sm)
                            DatePicker(selection: $repeatUntil, in: sendAt...,
                                       displayedComponents: [.date]) {
                                Text("Until")
                            }
                            .labelsHidden()
                            .accessibilityLabel(Text("Until"))
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.sm)
                    }
                }
            }
            .animation(reduceMotion ? nil : AppMotion.state, value: repeatRule)
            .animation(reduceMotion ? nil : AppMotion.state, value: hasEndDate)
        }
    }

    private var repeatRuleRow: some View {
        HStack {
            Label("sl_repeat", systemImage: "repeat")
                .font(AppFont.subheadline).foregroundStyle(.primary)
            Spacer(minLength: AppSpacing.sm)
            Menu {
                Picker("sl_repeat", selection: $repeatRule) {
                    ForEach(SendLaterRepeat.allCases) { rule in
                        Text(rule.label).tag(rule)
                    }
                }
            } label: {
                HStack(spacing: AppSpacing.xxs) {
                    Text(repeatRule.label)
                        .font(AppFont.footnoteEmphasis)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(AppFont.caption2)
                }
                .foregroundStyle(Color.accentColor)
            }
            .accessibilityLabel(Text("sl_repeat"))
            .accessibilityValue(Text(repeatRule.label))
        }
    }

    // MARK: - Save

    private var saveArea: some View {
        // The "in the future" check must stay honest while the sheet idles,
        // so it re-evaluates on a coarse timeline instead of trusting the
        // last body render.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let timeIsPast = sendAt <= timeline.date
            VStack(spacing: AppSpacing.sm) {
                GlassWideButton(icon: "paperplane.fill",
                                label: editingItem == nil ? "Schedule" : "Update",
                                isBusy: isSaving,
                                isEnabled: canSave && !timeIsPast) {
                    Task { await save() }
                }
                if timeIsPast {
                    Label("sl_time_past", systemImage: "exclamationmark.triangle.fill")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.brandWarning)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Scheduled list

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader(icon: "list.bullet", title: "Scheduled")
            if service.items.isEmpty {
                emptyState
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(service.items) { item in
                        SwipeableRow(trailing: swipeActions(for: item)) {
                            scheduledRow(item)
                        }
                        .contextMenu {
                            Button {
                                beginEditing(item)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                Task { await service.cancel(item) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func swipeActions(for item: ScheduledMessage) -> [ConvSwipeAction] {
        [
            ConvSwipeAction(label: String(localized: "Edit"),
                            icon: "pencil", color: .brandPrimaryBlue) {
                beginEditing(item)
            },
            ConvSwipeAction(label: String(localized: "Delete"),
                            icon: "trash.fill", color: .red) {
                Task { await service.cancel(item) }
            }
        ]
    }

    private var emptyState: some View {
        card {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "calendar.badge.clock")
                    .font(AppFont.scaled(28, weight: .medium))
                    .foregroundStyle(Color.secondaryTextColor)
                Text("sl_empty_title")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                Text("sl_empty_sub")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.secondaryTextColor)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, AppSpacing.xl)
        }
    }

    private func scheduledRow(_ item: ScheduledMessage) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(item.body)
                .font(AppFont.body)
                .foregroundStyle(.primary)
                .lineLimit(1)
            if item.target == "dm", let recipient = item.dmRecipient {
                Text("sl_to \(recipient)")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.secondaryTextColor)
            }
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "clock")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.secondaryTextColor)
                if let next = item.nextSendDate {
                    Text(next.formatted(date: .abbreviated, time: .shortened))
                        .font(AppFont.caption)
                        .foregroundStyle(Color.secondaryTextColor)
                    Text(verbatim: "·")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.secondaryTextColor)
                    Text(next, format: .relative(presentation: .named))
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: AppSpacing.sm)
                if item.repeats {
                    repeatBadge(item)
                }
            }
            if item.repeats, let until = item.repeatUntilDate {
                Text("sl_until \(until.formatted(date: .abbreviated, time: .omitted))")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private func repeatBadge(_ item: ScheduledMessage) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Image(systemName: "repeat")
                .font(AppFont.caption2)
            Text(repeatLabel(item.repeatRule))
                .font(AppFont.caption2)
        }
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xxs)
        .background(Capsule().fill(Color.accentColor.opacity(AppOpacity.tintedFill)))
    }

    private func repeatLabel(_ rule: String) -> LocalizedStringKey {
        (SendLaterRepeat(rawValue: rule) ?? .once).label
    }

    // MARK: - Pieces

    private func sectionHeader(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(AppFont.caption2)
            Text(title)
                .font(AppFont.label)
                .textCase(.uppercase)
        }
        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
        .padding(.leading, AppSpacing.xxs)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .liquidGlass(cornerRadius: AppRadius.lg)
    }

    // MARK: - Editing

    private func beginEditing(_ item: ScheduledMessage) {
        let apply = {
            editingItem = item
            messageBody = item.body
            if let next = item.nextSendDate, next > Date() {
                sendAt = next
            } else {
                sendAt = SendLaterQuickPick.roundedUp(Date().addingTimeInterval(3600))
            }
            repeatRule = SendLaterRepeat(rawValue: item.repeatRule) ?? .once
            if let until = item.repeatUntilDate {
                hasEndDate = true
                repeatUntil = max(until, sendAt)
            } else {
                hasEndDate = false
            }
            activeChip = nil
            chipAppliedDate = nil
        }
        if reduceMotion { apply() } else { withAnimation(AppMotion.state) { apply() } }
    }

    private func cancelEditing() {
        let apply = {
            editingItem = nil
            messageBody = ""
            sendAt = SendLaterQuickPick.roundedUp(Date().addingTimeInterval(3600))
            repeatRule = .once
            hasEndDate = false
            activeChip = nil
            chipAppliedDate = nil
        }
        if reduceMotion { apply() } else { withAnimation(AppMotion.state) { apply() } }
    }

    // MARK: - Save

    private func save() async {
        guard let pid = propertyId, canSave, sendAt > Date() else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.schedule(
                propertyId: pid,
                authorId: authorId,
                authorName: authorName,
                target: target,
                dmRecipient: dmRecipient,
                body: trimmedBody,
                firstSendAt: sendAt,
                repeatRule: repeatRule.rawValue,
                repeatUntil: scheduledRepeatUntil
            )
            if let old = editingItem {
                // No update API — the replacement is live, now retire the
                // original. If that fails, say so instead of dismissing over
                // a duplicate.
                await service.cancel(old)
                editingItem = nil
                if service.items.contains(where: { $0.id == old.id }) {
                    errorMessage = service.error ?? String(localized: "sl_edit_cleanup_failed")
                    return
                }
            }
            HapticFeedback.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
