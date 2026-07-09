import SwiftUI
import EventKit
import UserNotifications

struct AddTaskView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss

    var editing: MaintenanceTask? = nil

    @State private var title = ""
    @State private var description = ""
    @State private var priority = "medium"
    @State private var category = "maintenance"
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(86400 * 3)
    @State private var hasDueTime = false
    @State private var dueTime = Date()
    @State private var isSaving = false
    @State private var errorMsg: String?
    @State private var assigneeIds: [String] = []
    @State private var assigneeNames: [String] = []
    @State private var showAssigneePicker = false
    @State private var addToCalendar = false
    @State private var addToReminders = false
    @State private var availableCalendars: [EKCalendar] = []
    @State private var selectedCalendarId: String? = nil
    @State private var syncHint: String? = nil

    let priorities  = ["low", "medium", "high", "critical"]
    let categories  = ["maintenance", "repair", "inspection", "cleaning", "upgrade", "administrative", "other"]

    var body: some View {
        FormScaffold(title: editing != nil ? "Edit Task" : "New Task",
                     saveLabel: editing != nil ? "Save Changes" : "Add Task",
                     canSave: canSave, isSaving: isSaving,
                     error: $errorMsg, onSave: { save() }) {
            titleField
            descriptionField
            priorityPicker
            categoryPicker
            dueDatePicker
            assigneesSection
            calendarToggle
            workedTimeRow
        }
        .sheet(isPresented: $showAssigneePicker) {
            AssigneePickerSheet(assigneeIds: $assigneeIds, assigneeNames: $assigneeNames)
        }
        .onAppear { populateFromEditing() }
        .task { await familyService.load() }
    }

    private func populateFromEditing() {
        guard let t = editing else { return }
        title = t.title
        description = t.description ?? ""
        priority = t.priority
        category = t.category
        assigneeIds = t.assigneeIds
        assigneeNames = t.assigneeNames
        if let ds = t.dueDate, let d = MaintenanceTask.parseDate(ds) {
            hasDueDate = true
            dueDate = d
            if ds.count > 10 {
                hasDueTime = true
                dueTime = d
            }
        }
    }

    // MARK: - Fields

    /// The total time logged against this task by the work-session timer —
    /// shown only when editing an existing task that has recorded time.
    @ViewBuilder
    private var workedTimeRow: some View {
        if let t = editing {
            // The larger of the local App Group total and the server mirror —
            // so the number is right whether this device banked the time or
            // another one did (once migration 136's column ships).
            let worked = max(WorkSessionStore.shared.workedSeconds(for: t.id),
                             TimeInterval(t.workedSeconds))
            if worked > 0 {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "timer")
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(Color.brandSuccess)
                        .frame(width: 34, height: 34)
                        .glassCircle()
                    Text("session_worked_total")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.secondaryTextColor)
                    Spacer()
                    Text(verbatim: worked.workedTotalDisplay)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .padding(AppSpacing.base)
                .liquidGlass(cornerRadius: AppRadius.md)
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Title")
            TextField("What needs to be done?", text: $title)
                .font(AppFont.scaled(16))
                .foregroundStyle(.primary)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Description (optional)")
            TextField("Add details…", text: $description, axis: .vertical)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .lineLimit(3...6)
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        }
    }

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Priority")
            HStack(spacing: 8) {
                ForEach(priorities, id: \.self) { p in
                    Button { priority = p } label: {
                        Text(LocalizedStringKey(p.capitalized))
                            .font(AppFont.scaled(13, weight: priority == p ? .semibold : .regular))
                            .foregroundStyle(priority == p ? Color.black : Color.primary.opacity(0.6))
                            .padding(.horizontal, 13).padding(.vertical, AppSpacing.sm)
                            .background(priority == p ? priorityColor(p) : Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { cat in
                        Button { category = cat } label: {
                            Text(LocalizedStringKey(cat.capitalized))
                                .font(AppFont.scaled(13, weight: category == cat ? .semibold : .regular))
                                .foregroundStyle(category == cat ? Color.black : Color.primary.opacity(0.6))
                                .padding(.horizontal, 13).padding(.vertical, AppSpacing.sm)
                                .background(category == cat ? Color.white : Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var dueDatePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $hasDueDate.animation()) {
                fieldLabel("Due Date")
            }
            .tint(.accentColor)
            if hasDueDate {
                HStack(spacing: 12) {
                    DatePicker("", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(.accentColor)
                    Spacer()
                    Button {
                        withAnimation { hasDueTime.toggle() }
                    } label: {
                        Label(hasDueTime ? "Remove time" : "Add time", systemImage: "clock")
                            .font(AppFont.scaled(13, weight: .medium))
                            .foregroundStyle(hasDueTime ? .accentColor : Color.primary.opacity(AppOpacity.secondaryText))
                            .labelStyle(.iconOnly)
                            .padding(AppSpacing.sm)
                            .background(hasDueTime ? Color.accentColor.opacity(0.12) : Color.primary.opacity(AppOpacity.subtleFill),
                                        in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                if hasDueTime {
                    DatePicker("", selection: $dueTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(.accentColor)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Assignees

    private var assigneesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Assign To")
            Button {
                HapticFeedback.impact(.light)
                showAssigneePicker = true
            } label: {
                HStack(spacing: 10) {
                    if assigneeIds.isEmpty {
                        Image(systemName: "person.badge.plus")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Text("Add team members…")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    } else {
                        ForEach(Array(zip(assigneeIds, assigneeNames)), id: \.0) { _, name in
                            if let member = familyService.members.first(where: { $0.name == name }) {
                                MemberAvatar(member: member, size: 30)
                            } else {
                                personIcon(name: name)
                            }
                        }
                        Text(assigneeNames.joined(separator: ", "))
                            .font(AppFont.scaled(13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: AppRadius.md))
            }
            .buttonStyle(.plain)
        }
    }

    private func personIcon(name: String) -> some View {
        ZStack {
            Circle().fill(.blue.opacity(0.25))
            Text(String(name.prefix(1)).uppercased()).font(AppFont.scaled(11, weight: .bold)).foregroundStyle(Color.accentColor)
        }
        .frame(width: 30, height: 30)
    }

    // MARK: - Calendar & Reminders sync

    private var calendarToggle: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add to Calendar")
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    if !hasDueDate {
                        Text("Set a due date to enable")
                            .font(AppFont.scaled(11))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                Spacer()
                Toggle("", isOn: $addToCalendar)
                    .tint(.accentColor)
                    .labelsHidden()
                    .disabled(!hasDueDate)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)

            if addToCalendar && hasDueDate && !availableCalendars.isEmpty {
                syncDivider
                calendarPickerRow
            }

            syncDivider

            HStack(spacing: 12) {
                Image(systemName: "checklist")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.brandWarning)
                    .frame(width: 28)
                Text("Add to Apple Reminders")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $addToReminders)
                    .tint(.accentColor)
                    .labelsHidden()
                    .disabled(!hasDueDate)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)

            if let syncHint {
                Text(syncHint)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.brandWarning)
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.bottom, AppSpacing.md)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        .opacity(hasDueDate ? 1 : 0.5)
        .onChange(of: addToCalendar) { _, on in
            guard on else { return }
            Task { await prepareCalendarAccess() }
        }
        .onChange(of: addToReminders) { _, on in
            guard on else { return }
            Task {
                if !(await TaskCalendarSync.requestReminderAccess()) {
                    addToReminders = false
                    syncHint = String(localized: "Allow Reminders access in Settings to use this.")
                }
            }
        }
    }

    private var syncDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private var selectedCalendar: EKCalendar? {
        availableCalendars.first { $0.calendarIdentifier == selectedCalendarId }
    }

    private var calendarPickerRow: some View {
        Menu {
            ForEach(calendarSources, id: \.self) { source in
                Section(source) {
                    ForEach(availableCalendars.filter { ($0.source?.title ?? "") == source },
                            id: \.calendarIdentifier) { cal in
                        Button {
                            selectedCalendarId = cal.calendarIdentifier
                        } label: {
                            if cal.calendarIdentifier == selectedCalendarId {
                                Label(cal.title, systemImage: "checkmark")
                            } else {
                                Text(cal.title)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(selectedCalendar.map { Color(UIColor(cgColor: $0.cgColor)) } ?? Color.accentColor)
                    .frame(width: 10, height: 10)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCalendar?.title ?? String(localized: "Default calendar"))
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                    if let source = selectedCalendar?.source?.title, !source.isEmpty {
                        Text(source)
                            .font(AppFont.scaled(11))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(0.35))
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var calendarSources: [String] {
        var seen = Set<String>()
        return availableCalendars.compactMap { cal in
            let title = cal.source?.title ?? ""
            return seen.insert(title).inserted ? title : nil
        }
    }

    private func prepareCalendarAccess() async {
        switch await TaskCalendarSync.requestEventAccess() {
        case .full:
            availableCalendars = TaskCalendarSync.writableCalendars()
            if selectedCalendarId == nil {
                selectedCalendarId = TaskCalendarSync.defaultCalendarId
            }
            syncHint = nil
        case .writeOnly:
            // Can save to the default calendar but not list others.
            availableCalendars = []
            syncHint = nil
        case .denied:
            addToCalendar = false
            syncHint = String(localized: "Allow Calendar access in Settings to use this.")
        }
    }

    // MARK: - Save

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (editing != nil || propertyService.primary != nil)
    }

    private func save() {
        isSaving = true
        errorMsg = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description
        let combinedDueDate: Date = {
            guard hasDueTime else { return dueDate }
            let cal = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: dueDate)
            let timeComps = cal.dateComponents([.hour, .minute], from: dueTime)
            comps.hour = timeComps.hour; comps.minute = timeComps.minute
            return cal.date(from: comps) ?? dueDate
        }()
        let dueDateStr: String? = {
            guard hasDueDate else { return nil }
            return (hasDueTime ? AppDate.dayTime : AppDate.day).string(from: combinedDueDate)
        }()

        Task {
            do {
                let savedTaskId: UUID
                if let existing = editing {
                    try await taskService.updateTask(
                        existing,
                        title: trimmedTitle,
                        description: trimmedDesc,
                        dueDate: dueDateStr,
                        priority: priority,
                        category: category,
                        assigneeIds: assigneeIds,
                        assigneeNames: assigneeNames
                    )
                    savedTaskId = existing.id
                } else {
                    guard let propId = propertyService.primary?.id else {
                        errorMsg = String(localized: "No property found. Please set up your property first.")
                        isSaving = false
                        return
                    }
                    let payload = NewTaskPayload(
                        propertyId: propId,
                        title: trimmedTitle,
                        description: trimmedDesc,
                        dueDate: dueDateStr,
                        priority: priority,
                        category: category,
                        assigneeIds: assigneeIds,
                        assigneeNames: assigneeNames
                    )
                    let created = try await taskService.addTask(payload)
                    savedTaskId = created.id
                    scheduleAssigneeNotifications()
                }
                if hasDueDate {
                    if addToCalendar {
                        TaskCalendarSync.addEvent(title: trimmedTitle, notes: trimmedDesc,
                                                  date: combinedDueDate, hasTime: hasDueTime,
                                                  calendarId: selectedCalendarId)
                    }
                    if addToReminders {
                        // The link is what makes completion travel both ways:
                        // checking the reminder off in the Reminders app
                        // completes this task on next foreground, and vice versa.
                        if let reminderId = TaskCalendarSync.addReminder(
                            title: trimmedTitle, notes: trimmedDesc,
                            date: combinedDueDate, hasTime: hasDueTime) {
                            TaskReminderLinks.link(taskId: savedTaskId, reminderId: reminderId)
                        }
                    }
                }
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: - Assignee notifications

    private func scheduleAssigneeNotifications() {
        guard !assigneeNames.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let taskTitle = title.trimmingCharacters(in: .whitespaces)
        let display = DateFormatter(); display.locale = .current; display.dateStyle = .medium
        let dateStr = hasDueDate ? display.string(from: dueDate) : ""
        for name in assigneeNames {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Task assigned")
            content.body = dateStr.isEmpty
                ? String(format: String(localized: "%@, you have a new task: \"%@\""), name, taskTitle)
                : String(format: String(localized: "%@, you have a new task: \"%@\" · Due: %@"), name, taskTitle, dateStr)
            content.sound = .default
            content.badge = 1
            let req = UNNotificationRequest(
                identifier: "task.assign.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            )
            center.add(req)
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ key: LocalizedStringKey) -> some View {
        Text(key).font(AppFont.scaled(13, weight: .medium)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "critical": return Color.brandDanger
        case "high":     return .orange
        case "medium":   return Color(red: 1, green: 0.85, blue: 0.25)
        default:         return Color(red: 0.3, green: 0.9, blue: 0.5)
        }
    }
}
