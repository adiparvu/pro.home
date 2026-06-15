import SwiftUI

// MARK: - DeliveriesView

struct DeliveriesView: View {
    @EnvironmentObject private var deliveryService: DeliveryService
    @EnvironmentObject private var tabBarVis: TabBarVisibility

    @State private var showAddDelivery = false
    @State private var editingDelivery: Delivery? = nil
    @State private var showCompleted = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Deliveries", subtitle: "PROPERTY")

            if deliveryService.deliveries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddDelivery = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAddDelivery) {
            DeliveryFormSheet(editingDelivery: nil)
                .environmentObject(deliveryService)
        }
        .sheet(item: $editingDelivery) { delivery in
            DeliveryFormSheet(editingDelivery: delivery)
                .environmentObject(deliveryService)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                summaryPill

                if !deliveryService.activeDeliveries.isEmpty {
                    activeSection
                }

                completedSection

                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: ScrollOffsetKey.self,
                        value: geo.frame(in: .named("deliveriesScroll")).minY
                    )
                }
            )
        }
        .coordinateSpace(name: "deliveriesScroll")
        .onPreferenceChange(ScrollOffsetKey.self) { y in
            tabBarVis.scrollOffset = y
        }
    }

    // MARK: - Summary pill

    private var summaryPill: some View {
        let active = deliveryService.activeDeliveries.count
        let delivered = deliveryService.deliveries.filter { !$0.isActive }.count
        return HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                Text("\(active) active")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 14)
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.2, green: 0.80, blue: 0.4))
                    .frame(width: 8, height: 8)
                Text("\(delivered) delivered")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
            }
            if !deliveryService.todayDeliveries.isEmpty {
                Rectangle()
                    .fill(Color.primary.opacity(0.15))
                    .frame(width: 1, height: 14)
                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("\(deliveryService.todayDeliveries.count) today")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .glassCapsule()
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Active section

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("IN PROGRESS · \(deliveryService.activeDeliveries.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
            }
            .padding(.leading, 4)

            VStack(spacing: 10) {
                ForEach(deliveryService.activeDeliveries) { delivery in
                    DeliveryRow(delivery: delivery) {
                        editingDelivery = delivery
                    }
                    .environmentObject(deliveryService)
                }
            }
        }
    }

    // MARK: - Completed section

    private var completedSection: some View {
        let completed = deliveryService.deliveries.filter { !$0.isActive }
        guard !completed.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35)) { showCompleted.toggle() }
                    HapticFeedback.selection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("DELIVERED · \(completed.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                        Spacer()
                    }
                    .foregroundStyle(Color(red: 0.2, green: 0.80, blue: 0.4))
                    .padding(.leading, 4)
                }
                .buttonStyle(.plain)

                if showCompleted {
                    VStack(spacing: 10) {
                        ForEach(completed) { delivery in
                            DeliveryRow(delivery: delivery) {
                                editingDelivery = delivery
                            }
                            .environmentObject(deliveryService)
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "shippingbox")
                .font(.system(size: 56))
                .foregroundStyle(Color.primary.opacity(0.12))
            Text("No deliveries tracked")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Add packages to track\nyour deliveries.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
            Button { showAddDelivery = true } label: {
                Label("Add first delivery", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(
                        Color.blue,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - DeliveryRow

struct DeliveryRow: View {
    @EnvironmentObject private var deliveryService: DeliveryService
    let delivery: Delivery
    let onEdit: () -> Void

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                // Status icon in colored circle
                ZStack {
                    Circle()
                        .fill(delivery.statusColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: delivery.statusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(delivery.statusColor)
                }

                // Middle content
                VStack(alignment: .leading, spacing: 3) {
                    Text(delivery.description)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(delivery.carrier)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        if !delivery.trackingNumber.isEmpty {
                            Text("·")
                                .foregroundStyle(Color.primary.opacity(0.3))
                            Text(delivery.trackingNumber)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.45))
                                .lineLimit(1)
                        }
                    }

                    if let expected = delivery.expectedDisplay {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.primary.opacity(0.35))
                            Text(expected)
                                .font(.system(size: 11))
                                .foregroundStyle(
                                    expected == "Today"
                                        ? Color.orange
                                        : Color.primary.opacity(0.4)
                                )
                        }
                    }
                }

                Spacer()

                // Status badge
                Text(delivery.statusLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(delivery.statusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        delivery.statusColor.opacity(0.13),
                        in: Capsule()
                    )
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if delivery.isActive {
                Button {
                    HapticFeedback.success()
                    deliveryService.markDelivered(delivery)
                } label: {
                    Label("Delivered", systemImage: "checkmark.seal.fill")
                }
                .tint(Color(red: 0.2, green: 0.78, blue: 0.4))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticFeedback.warning()
                deliveryService.delete(delivery)
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                HapticFeedback.impact(.light)
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.accentColor)
        }
        .contextMenu {
            if delivery.isActive {
                Button {
                    HapticFeedback.success()
                    deliveryService.markDelivered(delivery)
                } label: {
                    Label("Mark as delivered", systemImage: "checkmark.seal.fill")
                }
            }

            Button {
                HapticFeedback.impact(.light)
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            Button {
                UIPasteboard.general.string = delivery.trackingNumber
                HapticFeedback.selection()
            } label: {
                Label("Copy tracking", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                HapticFeedback.warning()
                deliveryService.delete(delivery)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - DeliveryFormSheet (Add + Edit)

struct DeliveryFormSheet: View {
    @EnvironmentObject private var deliveryService: DeliveryService
    @Environment(\.dismiss) private var dismiss

    let editingDelivery: Delivery?

    @State private var description: String
    @State private var carrier: String
    @State private var trackingNumber: String
    @State private var status: String
    @State private var hasExpectedDate: Bool
    @State private var expectedDate: Date
    @State private var notes: String
    @State private var isSaving = false

    private var isEditing: Bool { editingDelivery != nil }

    private var canSave: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    init(editingDelivery: Delivery?) {
        self.editingDelivery = editingDelivery

        if let d = editingDelivery {
            _description    = State(initialValue: d.description)
            _carrier        = State(initialValue: d.carrier)
            _trackingNumber = State(initialValue: d.trackingNumber)
            _status         = State(initialValue: d.status)
            _notes          = State(initialValue: d.notes ?? "")

            if let ds = d.expectedDate,
               let parsed = Self.parseExpectedDate(ds) {
                _hasExpectedDate = State(initialValue: true)
                _expectedDate    = State(initialValue: parsed)
            } else {
                _hasExpectedDate = State(initialValue: false)
                _expectedDate    = State(initialValue: Date())
            }
        } else {
            _description    = State(initialValue: "")
            _carrier        = State(initialValue: Delivery.carrierOptions.first ?? "DHL")
            _trackingNumber = State(initialValue: "")
            _status         = State(initialValue: "ordered")
            _hasExpectedDate = State(initialValue: false)
            _expectedDate   = State(initialValue: Date())
            _notes          = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        descriptionField
                        carrierPickerSection
                        trackingField
                        statusPickerSection
                        expectedDateSection
                        notesField
                        saveButton
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .navigationTitle(isEditing ? "Edit delivery" : "New delivery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Fields

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("DESCRIPTION *")
            TextField("e.g. Laptop, Shoes, Book…", text: $description)
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var trackingField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("TRACKING CODE")
            TextField("ex. 1Z999AA10123456784", text: $trackingNumber)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("NOTES (OPTIONAL)")
            TextField("Additional notes…", text: $notes, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .lineLimit(2...4)
                .padding(14)
                .background(
                    Color.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
    }

    // MARK: Carrier picker

    private var carrierPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("CARRIER")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Delivery.carrierOptions, id: \.self) { c in
                        Button {
                            carrier = c
                            HapticFeedback.selection()
                        } label: {
                            Text(c)
                                .font(.system(size: 13, weight: carrier == c ? .semibold : .regular))
                                .foregroundStyle(carrier == c ? .white : Color.primary.opacity(0.65))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    carrier == c ? Color.blue : Color.primary.opacity(0.07),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: Status picker

    private var statusPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("STATUS")
            VStack(spacing: 0) {
                ForEach(Array(Delivery.statusOptions.enumerated()), id: \.element.id) { idx, opt in
                    Button {
                        status = opt.id
                        HapticFeedback.selection()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(statusColor(for: opt.id).opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: statusIcon(for: opt.id))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(statusColor(for: opt.id))
                            }
                            Text(opt.label)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                            Spacer()
                            if status == opt.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if idx < Delivery.statusOptions.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 0.5)
                            .padding(.leading, 58)
                    }
                }
            }
            .liquidGlass(cornerRadius: 16)
        }
    }

    private func statusColor(for id: String) -> Color {
        switch id {
        case "ordered":          return .gray
        case "in_transit":       return .blue
        case "out_for_delivery": return .orange
        case "delivered":        return Color(red: 0.2, green: 0.80, blue: 0.4)
        default:                 return .gray
        }
    }

    private func statusIcon(for id: String) -> String {
        switch id {
        case "ordered":          return "shippingbox.fill"
        case "in_transit":       return "airplane"
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        default:                 return "shippingbox"
        }
    }

    // MARK: Expected date

    private var expectedDateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("ESTIMATED DELIVERY DATE")

            GlassCard(padding: 14) {
                VStack(spacing: 12) {
                    Toggle(isOn: $hasExpectedDate) {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue)
                            Text("Set estimated date")
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                        }
                    }
                    .tint(.accentColor)

                    if hasExpectedDate {
                        Divider().opacity(0.3)
                        DatePicker(
                            "",
                            selection: $expectedDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .tint(.accentColor)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
    }

    // MARK: Save button

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text(isEditing ? "Save changes" : "Add delivery")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                canSave ? Color.blue : Color.primary.opacity(0.2),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(
                canSave ? Color.white : Color.primary.opacity(0.4)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
    }

    // MARK: Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    private static func parseExpectedDate(_ string: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: string)
    }

    private func expectedDateString() -> String? {
        guard hasExpectedDate else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: expectedDate)
    }

    private func save() {
        let trimmedDesc = description.trimmingCharacters(in: .whitespaces)
        guard !trimmedDesc.isEmpty else { return }
        isSaving = true

        let now = ISO8601DateFormatter().string(from: Date())

        if var existing = editingDelivery {
            existing.description     = trimmedDesc
            existing.carrier         = carrier
            existing.trackingNumber  = trackingNumber.trimmingCharacters(in: .whitespaces)
            existing.status          = status
            existing.expectedDate    = expectedDateString()
            existing.notes           = notes.trimmingCharacters(in: .whitespaces).isEmpty
                                          ? nil
                                          : notes.trimmingCharacters(in: .whitespaces)
            deliveryService.update(existing)
        } else {
            let delivery = Delivery(
                id: UUID(),
                carrier: carrier,
                trackingNumber: trackingNumber.trimmingCharacters(in: .whitespaces),
                description: trimmedDesc,
                status: status,
                expectedDate: expectedDateString(),
                notes: notes.trimmingCharacters(in: .whitespaces).isEmpty
                          ? nil
                          : notes.trimmingCharacters(in: .whitespaces),
                createdAt: now
            )
            deliveryService.add(delivery)
        }

        HapticFeedback.success()
        isSaving = false
        dismiss()
    }
}
