import SwiftUI
import EventKit
import UserNotifications

struct AddTaskView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var familyService: FamilyService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var priority = "medium"
    @State private var category = "maintenance"
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(86400 * 3)
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
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticFeedback.selection()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(isPresented: $showAssigneePicker) {
                AssigneePickerSheet(assigneeIds: $assigneeIds, assigneeNames: $assigneeNames)
            }
        }
        .task { await familyService.load() }
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Title")
            TextField("What needs to be done?", text: $title)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Priority")
            HStack(spacing: 8) {
                ForEach(priorities, id: \.self) { p in
                    Button { priority = p } label: {
                        Text(p.capitalized)
                            .font(.system(size: 13, weight: priority == p ? .semibold : .regular))
                            .foregroundStyle(priority == p ? Color.black : Color.primary.opacity(0.6))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(priority == p ? priorityColor(p) : Color.primary.opacity(0.07), in: Capsule())
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
                            Text(cat.capitalized)
                                .font(.system(size: 13, weight: category == cat ? .semibold : .regular))
                                .foregroundStyle(category == cat ? Color.black : Color.primary.opacity(0.6))
                                .padding(.horizontal, 13).padding(.vertical, 8)
                                .background(category == cat ? Color.white : Color.primary.opacity(0.07), in: Capsule())
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
            .tint(.blue)
            if hasDueDate {
                DatePicker("", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(.blue)
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
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
                .padding(14)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    private func personIcon(name: String) -> some View {
        ZStack {
            Circle().fill(.blue.opacity(0.25))
            Text(String(name.prefix(1)).uppercased()).font(.system(size: 11, weight: .bold)).foregroundStyle(.blue)
        }
        .frame(width: 30, height: 30)
    }

    // MARK: - Calendar toggle

    private var calendarToggle: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: calendarAdded ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    .font(.system(size: 14))
                    .foregroundStyle(calendarAdded ? Color(red: 0.3, green: 0.85, blue: 0.5) : Color.blue)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendarAdded ? "Added to Apple Calendar" : "Add to Apple Calendar")
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
                    .tint(.blue)
                    .labelsHidden()
                    .disabled(!hasDueDate)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .opacity(hasDueDate ? 1 : 0.5)
    }

    // MARK: - Save

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.black)
                } else {
                    Text("Add Task")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canSave ? Color.white : Color.primary.opacity(0.35))
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSave || isSaving)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && propertyService.primary != nil
    }

    private func save() {
        guard let propId = propertyService.primary?.id else {
            errorMsg = "No property found. Please set up your property first."
            return
        }
        isSaving = true
        errorMsg = nil

        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let payload = NewTaskPayload(
            propertyId: propId,
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description,
            dueDate: hasDueDate ? iso.string(from: dueDate) : nil,
            priority: priority,
            category: category,
            assigneeIds: assigneeIds,
            assigneeNames: assigneeNames
        )

        Task {
            do {
                try await taskService.addTask(payload)
                if addToCalendar && hasDueDate {
                    await addToAppleCalendar(title: payload.title, date: dueDate, notes: description)
                }
                scheduleAssigneeNotifications()
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
        let dateStr = hasDueDate ? DateFormatter().also { $0.dateStyle = .medium }.string(from: dueDate) : ""
        for name in assigneeNames {
            let content = UNMutableNotificationContent()
            content.title = "New Task Assigned"
            content.body = "\(name) – you have a new task: \"\(taskTitle)\"\(dateStr.isEmpty ? "" : " due \(dateStr)")"
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "task.assign.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
            )
            center.add(req)
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary.opacity(0.5))
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

// MARK: - Assignee picker sheet

struct AssigneePickerSheet: View {
    @EnvironmentObject private var familyService: FamilyService
    @Binding var assigneeIds: [String]
    @Binding var assigneeNames: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var customName = ""
    @State private var showCustom = false

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if !familyService.members.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FAMILY MEMBERS")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.35))
                                    .padding(.leading, 4)
                                MemberPickerView(selectedIds: $assigneeIds, selectedNames: $assigneeNames)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("SOMEONE ELSE")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.35))
                                .padding(.leading, 4)

                            if showCustom {
                                HStack(spacing: 10) {
                                    TextField("Name", text: $customName)
                                        .font(.system(size: 15)).foregroundStyle(.primary).tint(.blue)
                                        .padding(.horizontal, 14).padding(.vertical, 11)
                                        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                                    Button {
                                        let n = customName.trimmingCharacters(in: .whitespaces)
                                        guard !n.isEmpty else { return }
                                        let fakeId = "custom_\(n)"
                                        if !assigneeIds.contains(fakeId) {
                                            assigneeIds.append(fakeId)
                                            assigneeNames.append(n)
                                        }
                                        customName = ""
                                        showCustom = false
                                        HapticFeedback.success()
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 28)).foregroundStyle(.blue)
                                    }
                                }
                            } else {
                                Button {
                                    showCustom = true
                                    HapticFeedback.impact(.light)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "person.badge.plus").font(.system(size: 14)).foregroundStyle(.blue)
                                        Text("Add someone else…").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.6))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }

                            if !assigneeIds.filter({ $0.hasPrefix("custom_") }).isEmpty {
                                ForEach(assigneeIds.filter { $0.hasPrefix("custom_") }, id: \.self) { id in
                                    let name = String(id.dropFirst("custom_".count))
                                    HStack {
                                        Image(systemName: "person.fill").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.4))
                                        Text(name).font(.system(size: 14)).foregroundStyle(.primary)
                                        Spacer()
                                        Button {
                                            assigneeIds.removeAll { $0 == id }
                                            assigneeNames.removeAll { $0 == name }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.3))
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, 20).padding(.top, 8)
                }
            }
            .navigationTitle("Assign Task").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold)).foregroundStyle(.blue)
                }
            }
        }
    }
}

// MARK: - DateFormatter helper

extension DateFormatter {
    @discardableResult
    func also(_ block: (DateFormatter) -> Void) -> DateFormatter {
        block(self)
        return self
    }
}
