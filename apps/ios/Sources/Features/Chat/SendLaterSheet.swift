import SwiftUI

// MARK: - Send Later (scheduled messages)
//
// Compose-and-schedule sheet for the group chat and DM threads. The app only
// does CRUD on `scheduled_messages` — a server-side cron job delivers due
// rows every minute, so nothing here depends on the app being alive at send
// time. One sheet serves both conversation kinds via SendLaterContext.

enum SendLaterContext {
    case group(propertyId: UUID, authorId: UUID, authorName: String)
    case dm(propertyId: UUID?, authorId: UUID, authorName: String, recipientName: String)
}

struct SendLaterSheet: View {
    let context: SendLaterContext
    @Environment(\.dismiss) private var dismiss

    @State private var service = ScheduledMessageService()

    @State private var messageBody = ""
    @State private var sendAt: Date
    @State private var repeatRule = "once"
    @State private var indefinitely = true
    @State private var repeatUntil: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(context: SendLaterContext) {
        self.context = context
        let first = Self.defaultFirstSend()
        _sendAt = State(initialValue: first)
        _repeatUntil = State(initialValue: Calendar.current.date(byAdding: .month, value: 1, to: first) ?? first)
    }

    /// Now + 1 hour, rounded up to the next 5-minute mark — a tidy default
    /// that never lands in the past.
    private static func defaultFirstSend() -> Date {
        let base = Date().addingTimeInterval(3600)
        let step: TimeInterval = 5 * 60
        let rounded = (base.timeIntervalSinceReferenceDate / step).rounded(.up) * step
        return Date(timeIntervalSinceReferenceDate: rounded)
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

    private var trimmedBody: String {
        messageBody.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var canSave: Bool {
        propertyId != nil && !trimmedBody.isEmpty && !isSaving
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppSpacing.xl) {
                        messageCard
                        timingCard
                        saveButton
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

    private var timingCard: some View {
        card {
            DatePicker(selection: $sendAt, in: Date()...,
                       displayedComponents: [.date, .hourAndMinute]) {
                Label("Send at", systemImage: "clock.fill")
                    .font(AppFont.subheadline).foregroundStyle(.primary)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
            divider
            HStack {
                Label("Repeat", systemImage: "repeat")
                    .font(AppFont.subheadline).foregroundStyle(.primary)
                Spacer()
                Picker("", selection: $repeatRule.animation(.snappy)) {
                    Text("Once").tag("once")
                    Text("Daily").tag("daily")
                    Text("Weekly").tag("weekly")
                    Text("Monthly").tag("monthly")
                }
                .labelsHidden().pickerStyle(.menu).tint(.secondary)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.xs)
            if repeatRule != "once" {
                divider
                Toggle(isOn: $indefinitely.animation(.snappy)) {
                    Label {
                        Text("Indefinitely")
                            .font(AppFont.subheadline).foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: "infinity")
                    }
                }
                .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                if !indefinitely {
                    divider
                    DatePicker(selection: $repeatUntil, in: sendAt...,
                               displayedComponents: .date) {
                        Label("Until", systemImage: "calendar.badge.checkmark")
                            .font(AppFont.subheadline).foregroundStyle(.primary)
                    }
                    .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.sm)
                }
            }
        }
    }

    private var saveButton: some View {
        Button { Task { await save() } } label: {
            HStack(spacing: AppSpacing.sm) {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(AppFont.footnoteEmphasis)
                }
                Text("Schedule").font(AppFont.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .fill(canSave
                          ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor,
                                                                  Color.accentColor.opacity(0.75)],
                                                         startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.primary.opacity(0.18)))
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    // MARK: - Scheduled list

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Scheduled")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)
            if service.items.isEmpty {
                card {
                    Text("Nothing scheduled yet.")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.secondaryTextColor)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.lg)
                }
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(service.items) { item in
                        SwipeableRow(trailing: [
                            ConvSwipeAction(label: String(localized: "Delete"),
                                            icon: "trash.fill", color: .red) {
                                Task { await service.cancel(item) }
                            }
                        ]) {
                            scheduledRow(item)
                        }
                        .contextMenu {
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

    private func scheduledRow(_ item: ScheduledMessage) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(item.body)
                .font(AppFont.body)
                .foregroundStyle(.primary)
                .lineLimit(2)
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "clock")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.secondaryTextColor)
                Text((item.nextSendDate ?? Date())
                    .formatted(date: .abbreviated, time: .shortened))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.secondaryTextColor)
                Spacer()
                Text(repeatLabel(item.repeatRule))
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.14)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    private func repeatLabel(_ rule: String) -> LocalizedStringKey {
        switch rule {
        case "daily":   return "Daily"
        case "weekly":  return "Weekly"
        case "monthly": return "Monthly"
        default:        return "Once"
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .liquidGlass(cornerRadius: AppRadius.lg)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(AppOpacity.hairline))
            .frame(height: 0.5).padding(.leading, 52)
    }

    // MARK: - Save

    private func save() async {
        guard let pid = propertyId, canSave else { return }
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
                firstSendAt: max(sendAt, Date()),
                repeatRule: repeatRule,
                repeatUntil: (repeatRule != "once" && !indefinitely)
                    ? max(repeatUntil, sendAt) : nil
            )
            HapticFeedback.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
