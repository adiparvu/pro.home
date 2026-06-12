import SwiftUI

struct AddTaskView: View {
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var propertyService: PropertyService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var priority = "medium"
    @State private var category = "maintenance"
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(86400 * 3)
    @State private var isSaving = false
    @State private var errorMsg: String?

    let priorities = ["low", "medium", "high", "critical"]
    let categories = ["maintenance", "repair", "inspection", "cleaning", "upgrade", "administrative", "other"]

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
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Title")
            TextField("What needs to be done?", text: $title)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(14)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("Description (optional)")
            TextField("Add details…", text: $description, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.white)
                .lineLimit(3...6)
                .padding(14)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var priorityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Priority")
            HStack(spacing: 8) {
                ForEach(priorities, id: \.self) { p in
                    Button {
                        priority = p
                    } label: {
                        Text(p.capitalized)
                            .font(.system(size: 13, weight: priority == p ? .semibold : .regular))
                            .foregroundStyle(priority == p ? .black : .white.opacity(0.6))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(priority == p ? priorityColor(p) : .white.opacity(0.07), in: Capsule())
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
                        Button {
                            category = cat
                        } label: {
                            Text(cat.capitalized)
                                .font(.system(size: 13, weight: category == cat ? .semibold : .regular))
                                .foregroundStyle(category == cat ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(category == cat ? .white : .white.opacity(0.07), in: Capsule())
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
                    .colorScheme(.dark)
                    .tint(.blue)
            }
        }
    }

    // MARK: - Save

    private var saveButton: some View {
        Button {
            save()
        } label: {
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
            .background(canSave ? .white : .white.opacity(0.35))
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!canSave || isSaving)
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && propertyService.primary != nil
    }

    private func save() {
        guard let propId = propertyService.primary?.id else {
            errorMsg = "No property found. Please set up your property first."
            return
        }
        isSaving = true
        errorMsg = nil

        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"

        let payload = NewTaskPayload(
            propertyId: propId,
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description,
            dueDate: hasDueDate ? iso.string(from: dueDate) : nil,
            priority: priority,
            category: category
        )

        Task {
            do {
                try await taskService.addTask(payload)
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            isSaving = false
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
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
