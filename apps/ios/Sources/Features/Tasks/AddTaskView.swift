import SwiftUI
import EventKit
import UserNotifications

struct AddTaskView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService
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
    @State private var calendarAdded = false

    let priorities  = ["low", "medium", "high", "critical"]
    let categories  = ["maintenance", "repair", "inspection", "cleaning", "upgrade", "administrative", "other"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        titleField
                        descriptionField
                        priorityPicker
                        categoryPicker
                        dueDatePicker
                        assigneesSection
                        calendarToggle

                        if let errorMsg {
                            Text(errorMsg)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        saveButton
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(editing != nil ? String(localized: "Edit Task") : String(localized: "New Task"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticFeedback.selection()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAssigneePicker) {
                AssigneePickerSheet(assigneeIds: $assigneeIds, assigneeNames: $assigneeNames)
            }
            .onAppear { populateFromEditing() }
        }
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

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Title")
            TextField("What needs to be done?", text: $title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .padding(14)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Description (optional)")
            TextField("Add details…", text: $description, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .lineLimit(3...6)
                .padding(14)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Priority")
            HStack(spacing: 8) {
                ForEach(priorities, id: \.self) { p in
                    Button { priority = p } label: {
                        Text(LocalizedStringKey(p.capitalized))
                            .font(.system(size: 13, weight: priority == p ? .semibold : .regular))
                            .foregroundStyle(priority == p ? Color.black : Color.primary.opacity(0.6))
                            .padding(.horizontal, 13).padding(.vertical, 8)
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
                                .font(.system(size: 13, weight: category == cat ? .semibold : .regular))
                                .foregroundStyle(category == cat ? Color.black : Color.primary.opacity(0.6))
                                .padding(.horizontal, 13).padding(.vertical, 8)
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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(hasDueTime ? .accentColor : Color.primary.opacity(AppOpacity.secondaryText))
                            .labelStyle(.iconOnly)
                            .padding(8)
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
                            .font(.system(size: 14))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Text("Add team members…")
                            .font(.system(size: 14))
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
                            .font(.system(size: 13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
                .padding(14)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func personIcon(name: String) -> some View {
        ZStack {
            Circle().fill(.blue.opacity(0.25))
            Text(String(name.prefix(1)).uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.accentColor)
        }
        .frame(width: 30, height: 30)
    }

    // MARK: - Calendar toggle

    private var calendarToggle: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: calendarAdded ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(calendarAdded ? Color(red: 0.3, green: 0.85, blue: 0.5) : Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(calendarAdded ? "Added to Apple Calendar" : "Add to Apple Calendar"))
                        .font(.system(size: 15))
                        .foregroundStyle(.primary)
                    if !hasDueDate {
                        Text("Set a due date to enable")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                Spacer()
                Toggle("", isOn: $addToCalendar)
                    .tint(.accentColor)
                    .labelsHidden()
                    .disabled(!hasDueDate)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
        .opacity(hasDueDate ? 1 : 0.5)
    }

    // MARK: - Save

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.black)
                } else {
                    Text(LocalizedStringKey(editing != nil ? "Save Changes" : "Add Task"))
                        .font(AppFont.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSave ? Color.white : Color.primary.opacity(AppOpacity.disabled))
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSave || isSaving)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (editing != nil || propertyService.primary != nil)
    }

    private func save() {
        isSaving = true
        errorMsg = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description
        let dueDateStr: String? = {
            guard hasDueDate else { return nil }
            if hasDueTime {
                let cal = Calendar.current
                var comps = cal.dateComponents([.year, .month, .day], from: dueDate)
                let timeComps = cal.dateComponents([.hour, .minute], from: dueTime)
                comps.hour = timeComps.hour; comps.minute = timeComps.minute
                let combined = cal.date(from: comps) ?? dueDate
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
                return f.string(from: combined)
            } else {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                return f.string(from: dueDate)
            }
        }()

        Task {
            do {
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
                    try await taskService.addTask(payload)
                    if addToCalendar && hasDueDate {
                        await addToAppleCalendar(title: trimmedTitle, date: dueDate, notes: description)
                    }
                    scheduleAssigneeNotifications()
                }
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: - Apple Calendar

    private func addToAppleCalendar(title: String, date: Date, notes: String) async {
        let store = EKEventStore()
        let granted: Bool
        if #available(iOS 17, *) {
            granted = (try? await store.requestWriteOnlyAccessToEvents()) ?? false
        } else {
            granted = await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { ok, _ in cont.resume(returning: ok) }
            }
        }
        guard granted else { return }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = date
        event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: date) ?? date
        event.notes = notes.isEmpty ? nil : notes
        event.calendar = store.defaultCalendarForNewEvents
        try? store.save(event, span: .thisEvent)
        await MainActor.run { calendarAdded = true }
    }

    // MARK: - Assignee notifications

    private func scheduleAssigneeNotifications() {
        guard !assigneeNames.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let taskTitle = title.trimmingCharacters(in: .whitespaces)
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
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
        Text(key).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
    }

    private func priorityColor(_ p: String) -> Color {
        switch p {
        case "critical": return Color(red: 1, green: 0.25, blue: 0.25)
        case "high":     return .orange
        case "medium":   return Color(red: 1, green: 0.85, blue: 0.25)
        default:         return Color(red: 0.3, green: 0.9, blue: 0.5)
        }
    }
}
