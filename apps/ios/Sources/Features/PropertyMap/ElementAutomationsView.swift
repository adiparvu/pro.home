import SwiftUI

// Automations section in the element detail. Phase 1: reminder rules that
// schedule a local notification (and optionally create a maintenance task).

struct ElementAutomationsSection: View {
    let element: PropertyElement

    @StateObject private var service = AutomationService()
    @EnvironmentObject private var taskService: TaskService
    @State private var showAdd = false

    private var items: [ElementAutomation] { service.automations(for: element.id) }

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Automations", systemImage: "bolt.badge.clock")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20)).foregroundStyle(Color.accentColor)
                    }
                }

                if items.isEmpty {
                    Text("No automations yet").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(items) { a in
                        row(a)
                        if a.id != items.last?.id { Divider().opacity(0.1) }
                    }
                }
            }
        }
        .task { await service.load(elementId: element.id) }
        .sheet(isPresented: $showAdd) {
            AddElementAutomationSheet(element: element) { trigger, name, interval, onceDate, createsTask in
                Task {
                    let next = service.nextRunString(
                        trigger: trigger, intervalMonths: interval,
                        onceDate: onceDate, warrantyUntil: element.warrantyUntil
                    )
                    let payload = NewElementAutomation(
                        elementId: element.id, propertyId: element.propertyId,
                        name: name, triggerType: trigger.rawValue,
                        intervalMonths: trigger == .periodic ? interval : nil,
                        nextRun: next, createsTask: createsTask, isActive: true
                    )
                    let created = await service.add(payload)
                    if created != nil, createsTask, let next {
                        await createTask(name: name, due: next)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ a: ElementAutomation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: a.trigger.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(a.isActive ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(a.name).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(a.isActive ? .primary : .secondary)
                Text(a.summary + (a.createsTask ? " · " + String(localized: "creates task") : ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { a.isActive },
                set: { Task { await service.setActive(a, active: $0) } }
            ))
            .labelsHidden()
            .scaleEffect(0.8)
            Menu {
                Button(role: .destructive) { Task { await service.delete(a) } } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).padding(.leading, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func createTask(name: String, due: String) async {
        let payload = NewTaskPayload(
            propertyId: element.propertyId,
            title: name,
            description: String(format: String(localized: "Automation for %@"), element.name),
            dueDate: due,
            priority: "medium",
            category: "maintenance",
            assigneeIds: [],
            assigneeNames: []
        )
        try? await taskService.addTask(payload)
    }
}

// MARK: - Add automation sheet

struct AddElementAutomationSheet: View {
    let element: PropertyElement
    let onAdd: (_ trigger: AutomationTrigger, _ name: String, _ intervalMonths: Int, _ onceDate: Date, _ createsTask: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var trigger: AutomationTrigger = .periodic
    @State private var name = ""
    @State private var intervalMonths = 6
    @State private var onceDate = Date().addingTimeInterval(86400 * 30)
    @State private var createsTask = true

    private var availableTriggers: [AutomationTrigger] {
        element.warrantyUntil == nil ? [.periodic, .once] : AutomationTrigger.allCases
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Type", systemImage: "bolt").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(availableTriggers) { t in
                                            Button { withAnimation(.spring(response: 0.25)) { trigger = t } } label: {
                                                Label(t.displayName, systemImage: t.icon)
                                                    .font(.caption.weight(trigger == t ? .semibold : .regular))
                                                    .foregroundStyle(trigger == t ? .white : .secondary)
                                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                                    .background(Capsule().fill(trigger == t ? Color.accentColor : Color.primary.opacity(0.07)))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }

                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Name", systemImage: "textformat").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                TextField("e.g. Service the boiler", text: $name)
                                    .font(.subheadline)
                                    .padding(10)
                                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }

                        if trigger == .periodic {
                            GlassCard(padding: 14) {
                                Stepper(value: $intervalMonths, in: 1...60) {
                                    Text(String(format: String(localized: "Every %d month(s)"), intervalMonths)).font(.subheadline)
                                }
                            }
                        } else if trigger == .once {
                            GlassCard(padding: 14) {
                                DatePicker(String(localized: "Date"), selection: $onceDate, displayedComponents: .date)
                                    .font(.subheadline)
                            }
                        } else if trigger == .warranty {
                            GlassCard(padding: 14) {
                                Text(String(format: String(localized: "Alerts 7 days before warranty ends (%@)"), element.warrantyUntil ?? "—"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }

                        GlassCard(padding: 14) {
                            Toggle(isOn: $createsTask) {
                                Label("Also create a task", systemImage: "checklist").font(.subheadline)
                            }
                            .tint(Color.accentColor)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("New automation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? defaultName : name.trimmingCharacters(in: .whitespaces)
                        onAdd(trigger, finalName, intervalMonths, onceDate, createsTask)
                        HapticFeedback.success()
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
            .onAppear { if name.isEmpty { name = defaultName } }
        }
    }

    private var defaultName: String {
        switch trigger {
        case .periodic: return String(format: String(localized: "Check %@"), element.name)
        case .once:     return String(format: String(localized: "Reminder: %@"), element.name)
        case .warranty: return String(format: String(localized: "Warranty: %@"), element.name)
        }
    }
}
