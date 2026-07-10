import SwiftUI
import EventKit
import UserNotifications

struct AddTaskView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize

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
    @State private var existingPhotoUrls: [String] = []
    @State private var pendingPhotos: [UIImage] = []
    @State private var location: TaskLocationValue? = nil
    @Namespace private var chipNS

    let priorities  = TaskPriorityStyle.order
    let categories  = ["maintenance", "repair", "inspection", "cleaning", "upgrade", "administrative", "other"]

    private let descriptionLimit = 500

    /// The combined due-date the preview and the calendar sync both read.
    private var combinedDue: Date? {
        guard hasDueDate else { return nil }
        guard hasDueTime else { return dueDate }
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: dueDate)
        let t = cal.dateComponents([.hour, .minute], from: dueTime)
        comps.hour = t.hour; comps.minute = t.minute
        return cal.date(from: comps) ?? dueDate
    }

    var body: some View {
        NavigationStack {
            // The live preview column exists to show what a task will become —
            // valuable while CREATING, redundant while EDITING something that
            // already exists (and the user asked for it gone there). In edit
            // mode the form takes the full width on every size class.
            Group {
                if editing != nil {
                    formScroll
                } else if hSize == .regular {
                    HStack(alignment: .top, spacing: 0) {
                        formScroll
                            .frame(maxWidth: .infinity)
                        Divider()
                        previewScroll
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            formContent
                            preview
                        }
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.top, AppSpacing.md)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(Text(editing != nil ? "task_editor_edit_title" : "task_editor_new_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) { saveButton }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } }
            )) {
                Button("OK", role: .cancel) { errorMsg = nil }
            } message: { Text(errorMsg ?? "") }
        }
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showAssigneePicker) {
            AssigneePickerSheet(assigneeIds: $assigneeIds, assigneeNames: $assigneeNames)
        }
        .onAppear { populateFromEditing() }
        .task { await familyService.load() }
    }

    // MARK: - Save button (purple check)

    private var saveButton: some View {
        Group {
            if isSaving {
                ProgressView()
            } else {
                Button {
                    HapticFeedback.impact(.light)
                    save()
                } label: {
                    Image(systemName: "checkmark")
                        .font(AppFont.scaled(16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(
                            LinearGradient(colors: [Color.brandPurple, Color.brandPurple.opacity(0.82)],
                                           startPoint: .top, endPoint: .bottom),
                            in: Circle()
                        )
                        .opacity(canSave ? 1 : 0.4)
                        .shadow(color: Color.brandPurple.opacity(canSave ? 0.4 : 0), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityLabel(editing != nil ? "Save Changes" : "Add Task")
            }
        }
    }

    // MARK: - Layout pieces

    private var formScroll: some View {
        ScrollView(showsIndicators: false) {
            formContent
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, 40)
        }
    }

    private var previewScroll: some View {
        ScrollView(showsIndicators: false) {
            preview
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, 40)
        }
    }

    private var preview: some View {
        TaskPreviewPanel(
            title: title,
            description: description,
            priority: priority,
            category: category,
            dueDate: combinedDue,
            hasDueTime: hasDueTime,
            assigneeNames: assigneeNames,
            addToCalendar: addToCalendar && hasDueDate,
            addToReminders: addToReminders && hasDueDate
        )
        .environment(familyService)
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            detailsSection
            TaskPhotoSection(existingUrls: $existingPhotoUrls,
                             pendingImages: $pendingPhotos)
            priorityPicker
            categoryPicker
            dueDateSection
            TaskLocationSection(location: $location)
            assigneesSection
            syncSection
            workedTimeRow
        }
    }

    // MARK: - Details (title + description)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: "square.text.square", key: "task_editor_details")

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Title")
                HStack(spacing: 8) {
                    TextField(text: $title) { Text("What needs to be done?") }
                        .font(AppFont.scaled(16))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                    if !title.isEmpty {
                        Button { title = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.primary.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("Description (optional)")
                VStack(alignment: .trailing, spacing: 4) {
                    TextField(text: $description, axis: .vertical) { Text("Add details…") }
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .tint(.accentColor)
                        .lineLimit(3...6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onChange(of: description) { _, new in
                            if new.count > descriptionLimit {
                                description = String(new.prefix(descriptionLimit))
                            }
                        }
                    Text("\(description.count)/\(descriptionLimit)")
                        .font(AppFont.caption2)
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
        }
    }

    // MARK: - Priority

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "flag.fill", key: "Priority")
            HStack(spacing: 8) {
                ForEach(priorities, id: \.self) { p in
                    priorityChip(p)
                }
            }
        }
    }

    // Same Liquid Glass selection language as the category chips below —
    // `glassFilterCapsule` supplies the material, while the priority tint
    // stays visible through the colored dot and, when selected, the label.
    private func priorityChip(_ p: String) -> some View {
        let style = TaskPriorityStyle(p)
        let selected = priority == p
        return Button {
            HapticFeedback.selection()
            withAnimation(.taskSpring) { priority = p }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(style.color).frame(width: 8, height: 8)
                Text(style.label)
                    .font(AppFont.scaled(13, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? style.color : Color.primary.opacity(AppOpacity.emphasis))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .glassFilterCapsule(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Category

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "square.grid.2x2.fill", key: "Category")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categories, id: \.self) { cat in
                        categoryChip(cat)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    // Round Liquid Glass capsules (IMG_8215) — the same selection language as
    // the app's filter chips, replacing the old dark rectangular tiles.
    private func categoryChip(_ cat: String) -> some View {
        let style = TaskCategoryStyle(cat)
        let selected = category == cat
        return Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.25)) { category = cat }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: style.icon)
                    .font(AppFont.scaled(13, weight: .semibold))
                Text(style.label)
                    .font(AppFont.scaled(13, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(AppOpacity.emphasis))
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 9)
            .glassFilterCapsule(selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Due date

    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasDueDate.animation(.taskSpring)) {
                sectionHeader(icon: "calendar", key: "Due Date")
            }
            .tint(Color.brandPurple)

            if hasDueDate {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(AppFont.footnote)
                            .foregroundStyle(Color.brandPurple)
                            .frame(width: 22)
                        DatePicker("", selection: $dueDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .tint(Color.brandPurple)
                        Spacer()
                        Button {
                            withAnimation(.taskSpring) { hasDueTime.toggle() }
                        } label: {
                            Image(systemName: "clock")
                                .font(AppFont.scaled(15, weight: .medium))
                                .foregroundStyle(hasDueTime ? Color.brandPurple : Color.primary.opacity(AppOpacity.secondaryText))
                                .padding(AppSpacing.sm)
                                .background(hasDueTime ? Color.brandPurple.opacity(0.14) : Color.primary.opacity(AppOpacity.subtleFill),
                                            in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(hasDueTime ? "Remove time" : "Add time")
                    }
                    .padding(AppSpacing.base)
                    .background(Color.primary.opacity(AppOpacity.subtleFill),
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

                    if hasDueTime {
                        HStack {
                            Image(systemName: "clock.fill")
                                .font(AppFont.footnote)
                                .foregroundStyle(Color.brandPurple)
                                .frame(width: 22)
                            DatePicker("", selection: $dueTime, displayedComponents: .hourAndMinute)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(Color.brandPurple)
                            Spacer()
                        }
                        .padding(AppSpacing.base)
                        .background(Color.primary.opacity(AppOpacity.subtleFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }

    // MARK: - Assignees

    private var assigneesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "person.2.fill", key: "Assign To")
            Button {
                HapticFeedback.impact(.light)
                showAssigneePicker = true
            } label: {
                HStack(spacing: 10) {
                    if assigneeIds.isEmpty {
                        Image(systemName: "person.badge.plus")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Text("Add team members…")
                            .font(AppFont.scaled(15))
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
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
                .padding(AppSpacing.base)
                .background(Color.primary.opacity(AppOpacity.subtleFill),
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func personIcon(name: String) -> some View {
        ZStack {
            Circle().fill(Color.brandPrimaryBlue.opacity(0.22))
            Text(String(name.prefix(1)).uppercased())
                .font(AppFont.scaled(11, weight: .bold))
                .foregroundStyle(Color.brandPrimaryBlue)
        }
        .frame(width: 30, height: 30)
    }

    // MARK: - Sync (Calendar + Reminders)

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "arrow.triangle.2.circlepath", key: "task_sync_section")
            VStack(spacing: 0) {
                syncRow(icon: "calendar", tint: Color.brandPurple,
                        title: "Add to Calendar", subtitle: "task_calendar_hint",
                        isOn: $addToCalendar)

                if addToCalendar && hasDueDate && !availableCalendars.isEmpty {
                    syncDivider
                    calendarPickerRow
                }

                syncDivider

                syncRow(icon: "list.bullet", tint: Color.brandWarning,
                        title: "Add to Apple Reminders", subtitle: "task_reminders_hint",
                        isOn: $addToReminders)

                if let syncHint {
                    Text(syncHint)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.brandWarning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.bottom, AppSpacing.md)
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
            .opacity(hasDueDate ? 1 : 0.5)
        }
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

    private func syncRow(icon: String, tint: Color, title: LocalizedStringKey,
                         subtitle: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(AppOpacity.tintedFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.scaled(15, weight: .medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(AppFont.scaled(11))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .tint(Color.brandPurple)
                .labelsHidden()
                .disabled(!hasDueDate)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
    }

    private var syncDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 54)
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
                    .fill(selectedCalendar.map { Color(UIColor(cgColor: $0.cgColor)) } ?? Color.brandPurple)
                    .frame(width: 10, height: 10)
                    .frame(width: 30)
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
            availableCalendars = []
            syncHint = nil
        case .denied:
            addToCalendar = false
            syncHint = String(localized: "Allow Calendar access in Settings to use this.")
        }
    }

    // MARK: - Worked time (editing only)

    @ViewBuilder
    private var workedTimeRow: some View {
        if let t = editing {
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

    // MARK: - Populate

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
        existingPhotoUrls = t.photoUrls
        if let name = t.locationName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            location = TaskLocationValue(name: name, lat: t.locationLat, lon: t.locationLon)
        }
    }

    // MARK: - Save (unchanged business logic)

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (editing != nil || propertyService.primary != nil)
    }

    private func save() {
        isSaving = true
        errorMsg = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description
        let combinedDueDate: Date = combinedDue ?? dueDate
        let dueDateStr: String? = {
            guard hasDueDate else { return nil }
            return (hasDueTime ? AppDate.dayTime : AppDate.day).string(from: combinedDueDate)
        }()

        Task {
            do {
                // Photos upload first (both flows need the final URL list).
                guard let propId = editing?.propertyId ?? propertyService.primary?.id else {
                    errorMsg = String(localized: "No property found. Please set up your property first.")
                    isSaving = false
                    return
                }
                var allPhotoUrls = existingPhotoUrls
                if !pendingPhotos.isEmpty {
                    allPhotoUrls += try await TaskPhotoUploader.upload(pendingPhotos, propertyId: propId)
                }

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
                        assigneeNames: assigneeNames,
                        photoUrls: allPhotoUrls,
                        locationName: location?.name,
                        locationLat: location?.lat ?? nil,
                        locationLon: location?.lon ?? nil
                    )
                    savedTaskId = existing.id
                } else {
                    let payload = NewTaskPayload(
                        propertyId: propId,
                        title: trimmedTitle,
                        description: trimmedDesc,
                        dueDate: dueDateStr,
                        priority: priority,
                        category: category,
                        assigneeIds: assigneeIds,
                        assigneeNames: assigneeNames,
                        photoUrls: allPhotoUrls,
                        locationName: location?.name,
                        locationLat: location?.lat,
                        locationLon: location?.lon
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

    private func sectionHeader(icon: String, key: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.scaled(12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Text(key)
                .font(AppFont.scaled(14, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
        }
    }

    private func fieldLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.scaled(13, weight: .medium))
            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
    }
}
