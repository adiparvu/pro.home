import SwiftUI

// Create / edit / delete a household calendar event (Calendar C2). The day and
// (optional) time compose into the SAME wall-clock wire string tasks use, via
// the shared AppDate POSIX formatters, so HouseAgenda reads it back identically.
struct CalendarEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CalendarEventService.self) private var service

    let propertyId: UUID?
    /// The event being edited, or nil to create a new one on `defaultDay`.
    var existing: CalendarEvent? = nil
    var defaultDay: Date = Date()

    @State private var title = ""
    @State private var day = Date()
    @State private var allDay = true
    @State private var time = Date()
    @State private var location = ""
    @State private var notes = ""
    @State private var saving = false
    @State private var hydrated = false

    private var isEditing: Bool { existing != nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving && propertyId != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("cal_event_title", text: $title)
                        .font(AppFont.body)
                    DatePicker("cal_event_day", selection: $day, displayedComponents: .date)
                    Toggle("cal_event_all_day", isOn: $allDay.animation(.snappy(duration: 0.2)))
                    if !allDay {
                        DatePicker("cal_event_time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }
                Section {
                    TextField("cal_event_location", text: $location)
                    TextField("cal_event_notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) { deleteEvent() } label: {
                            Label("cal_delete_event", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(Text(isEditing ? "cal_edit_event" : "cal_new_event"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear(perform: hydrateOnce)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
    }

    // MARK: - State

    private func hydrateOnce() {
        guard !hydrated else { return }
        hydrated = true
        if let e = existing {
            title = e.title
            location = e.location ?? ""
            notes = e.notes ?? ""
            allDay = e.allDay
            let parsed = AppDate.day(from: e.startsAt) ?? defaultDay
            day = parsed
            time = parsed
        } else {
            day = defaultDay
            time = Date()
        }
    }

    /// Compose the wire string the app already speaks: a plain day, or a day + time.
    private func composeStartsAt() -> String {
        let cal = Calendar.current
        if allDay { return AppDate.day.string(from: day) }
        let dc = cal.dateComponents([.year, .month, .day], from: day)
        let tc = cal.dateComponents([.hour, .minute], from: time)
        var comps = DateComponents()
        comps.year = dc.year; comps.month = dc.month; comps.day = dc.day
        comps.hour = tc.hour; comps.minute = tc.minute
        let combined = cal.date(from: comps) ?? day
        return AppDate.dayTime.string(from: combined)
    }

    // MARK: - Actions

    private func save() {
        guard let pid = propertyId else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let starts = composeStartsAt()
        saving = true
        HapticFeedback.impact(.light)
        Task {
            if var e = existing {
                e.title = trimmed
                e.startsAt = starts
                e.allDay = allDay
                e.location = loc.isEmpty ? nil : loc
                e.notes = note.isEmpty ? nil : note
                await service.update(e)
            } else {
                _ = try? await service.create(
                    propertyId: pid, title: trimmed, notes: note.isEmpty ? nil : note,
                    startsAt: starts, endsAt: nil, allDay: allDay,
                    color: nil, location: loc.isEmpty ? nil : loc)
            }
            saving = false
            dismiss()
        }
    }

    private func deleteEvent() {
        guard let e = existing else { return }
        HapticFeedback.warning()
        Task { await service.delete(e); dismiss() }
    }
}
