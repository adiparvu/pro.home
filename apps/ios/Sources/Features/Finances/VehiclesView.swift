import SwiftUI

// MARK: - Vehicles — section, page, add/edit sheet
//
// "Garajul familiei": each car with its three deadlines color-coded by real
// days-left, the linked ledger costs (rows tagged "vehicle:<uuid>"), and the
// market value that flows into net worth.

// MARK: Section (embedded on FinancesView)

struct VehiclesSection: View {
    @Environment(VehicleService.self) private var service

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            NavigationLink { VehiclesView() } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text("vehicles_title")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            .buttonStyle(.plain)

            NavigationLink { VehiclesView() } label: {
                if service.vehicles.isEmpty {
                    EmptyStateView(icon: "car.fill",
                                   title: "vehicles_empty_title",
                                   message: "vehicles_empty_message")
                } else {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(service.vehicles.prefix(2)) { v in
                            compactRow(v)
                        }
                    }
                    .padding(AppSpacing.lg)
                    .liquidGlass(cornerRadius: AppRadius.xl)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func compactRow(_ v: Vehicle) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "car.fill")
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: v.name)
                    .font(AppFont.scaled(14, weight: .semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                if let next = nearestDeadline(v) {
                    Text(String(format: String(localized: "vehicle_next_deadline_fmt"),
                                String(localized: String.LocalizationValue(next.kind.rawValue == "itp" ? "vehicle_itp" : next.kind.rawValue == "insurance" ? "vehicle_insurance" : "vehicle_vignette")),
                                next.days))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(VehicleDeadline.tint(daysLeft: next.days))
                } else {
                    Text(verbatim: v.subtitle)
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.secondaryTextColor).lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private func nearestDeadline(_ v: Vehicle) -> (kind: VehicleDeadline, days: Int)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return VehicleDeadline.allCases.compactMap { k -> (VehicleDeadline, Int)? in
            guard let d = k.date(of: v) else { return nil }
            return (k, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: d)).day ?? 0)
        }
        .min { $0.1 < $1.1 }
        .map { (kind: $0.0, days: $0.1) }
    }
}

// MARK: Full page

struct VehiclesView: View {
    @Environment(VehicleService.self) private var service

    @State private var showAdd = false
    @State private var editing: Vehicle?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                if service.vehicles.isEmpty {
                    EmptyStateView(icon: "car.fill",
                                   title: "vehicles_empty_title",
                                   message: "vehicles_empty_message",
                                   actionLabel: "vehicle_add") { showAdd = true }
                        .padding(.top, AppSpacing.xxl)
                } else {
                    ForEach(service.vehicles) { v in
                        VehicleCard(vehicle: v,
                                    onEdit: { editing = v },
                                    onDelete: { Task { await service.delete(v) } })
                    }
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("vehicles_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel(Text("vehicle_add"))
            }
        }
        .sheet(isPresented: $showAdd) { VehicleFormSheet() }
        .sheet(item: $editing) { VehicleFormSheet(editing: $0) }
        .task { await service.load() }
        .refreshable { await service.load() }
    }
}

// MARK: One vehicle card

struct VehicleCard: View {
    @Environment(FinancialService.self) private var financialService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    let vehicle: Vehicle
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// All-time ledger cost anchored to this car via its tag.
    private var linkedCosts: Double {
        financialService.records
            .filter { $0.type == "expense" && $0.tags.contains(vehicle.ledgerTag) }
            .reduce(0) { $0 + currencyService.convert($1.amount, from: $1.currency,
                                                      to: appSettings.preferredCurrency) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.base) {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .fill(Color.accentColor.opacity(AppOpacity.tintedFill))
                    Image(systemName: "car.fill")
                        .font(AppFont.scaled(18, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: vehicle.name)
                        .font(AppFont.scaled(17, weight: .bold))
                        .foregroundStyle(.primary)
                    if !vehicle.subtitle.isEmpty {
                        Text(verbatim: vehicle.subtitle)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
                Spacer()
                if let value = vehicle.value, value > 0 {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: CurrencyService.money(value, code: vehicle.currency, whole: true))
                            .font(AppFont.scaled(15, weight: .bold))
                            .foregroundStyle(.primary).monospacedDigit()
                        Text("vehicle_value")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
            }

            VStack(spacing: AppSpacing.xs) {
                ForEach(VehicleDeadline.allCases) { kind in
                    if let d = kind.date(of: vehicle) {
                        deadlineRow(kind: kind, date: d)
                    }
                }
            }

            if linkedCosts > 0 {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "fuelpump.fill")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                    Text(String(format: String(localized: "vehicle_costs_fmt"),
                                CurrencyService.money(linkedCosts, code: appSettings.preferredCurrency, whole: true)))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .contextMenu {
            Button { onEdit() } label: { Label("vehicle_edit", systemImage: "pencil") }
            Button(role: .destructive) { onDelete() } label: {
                Label("vehicle_delete", systemImage: "trash")
            }
        }
    }

    private func deadlineRow(kind: VehicleDeadline, date: Date) -> some View {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        let tint = VehicleDeadline.tint(daysLeft: days)
        return HStack(spacing: AppSpacing.sm) {
            Image(systemName: kind.icon)
                .font(AppFont.scaled(13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(kind.label)
                .font(AppFont.scaled(13))
                .foregroundStyle(.primary)
            Spacer()
            Text(verbatim: AppDate.monthDayYear.string(from: date))
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.secondaryTextColor)
            Text(days < 0
                 ? String(localized: "vehicle_expired")
                 : String(format: String(localized: "vehicle_days_left_fmt"), days))
                .font(AppFont.scaled(12, weight: .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }
}

// MARK: Add / edit sheet

struct VehicleFormSheet: View {
    @Environment(VehicleService.self) private var service
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    var editing: Vehicle? = nil

    @State private var name = ""
    @State private var make = ""
    @State private var model = ""
    @State private var plate = ""
    @State private var yearText = ""
    @State private var fuel = "petrol"
    @State private var valueText = ""
    @State private var itpOn = false;       @State private var itpDate = Date()
    @State private var insuranceOn = false; @State private var insuranceDate = Date()
    @State private var vignetteOn = false;  @State private var vignetteDate = Date()
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var didHydrate = false

    private static let fuels = ["petrol", "diesel", "hybrid", "electric", "lpg", "other"]

    /// Literal keys ONLY (IMG_9273): a runtime-composed
    /// `String.LocalizationValue("fuel_\(f)")` interpolates into the KEY
    /// itself — the lookup becomes "fuel_%@", misses the catalog and renders
    /// the raw key on device. The compiler-checked switch cannot miss.
    private static func fuelLabel(_ f: String) -> String {
        switch f {
        case "petrol":   String(localized: "fuel_petrol")
        case "diesel":   String(localized: "fuel_diesel")
        case "hybrid":   String(localized: "fuel_hybrid")
        case "electric": String(localized: "fuel_electric")
        case "lpg":      String(localized: "fuel_lpg")
        default:         String(localized: "fuel_other")
        }
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        FormScaffold(title: editing == nil ? "vehicle_add" : "vehicle_edit",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: "car.fill", tint: .accentColor) {
                    TextField("vehicle_name_placeholder", text: $name).font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "textformat", tint: .accentColor) {
                    TextField("vehicle_make", text: $make).font(AppFont.body)
                    TextField("vehicle_model", text: $model).font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "number", tint: .accentColor) {
                    TextField("vehicle_plate", text: $plate)
                        .font(AppFont.body)
                        .textInputAutocapitalization(.characters)
                    Spacer()
                    TextField("vehicle_year", text: $yearText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(AppFont.body)
                        .frame(width: 70)
                }
                FormDivider()
                FormRow(icon: "fuelpump.fill", tint: .accentColor) {
                    Picker("vehicle_fuel", selection: $fuel) {
                        ForEach(Self.fuels, id: \.self) { f in
                            Text(Self.fuelLabel(f))
                                .tag(f)
                        }
                    }
                    .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "banknote.fill", tint: .accentColor) {
                    Text("vehicle_value").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $valueText).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).font(AppFont.body)
                    Text(verbatim: editing?.currency ?? appSettings.preferredCurrency)
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }

            FormGroup(title: "vehicle_deadlines") {
                deadlineToggle("vehicle_itp", icon: "checkmark.seal.fill", on: $itpOn, date: $itpDate)
                FormDivider()
                deadlineToggle("vehicle_insurance", icon: "shield.fill", on: $insuranceOn, date: $insuranceDate)
                FormDivider()
                deadlineToggle("vehicle_vignette", icon: "road.lanes", on: $vignetteOn, date: $vignetteDate)
            }

            FormGroup {
                FormRow(icon: "text.alignleft", tint: .accentColor) {
                    TextField("vehicle_notes_placeholder", text: $notes).font(AppFont.body)
                }
            }
        }
        .onAppear(perform: hydrate)
    }

    @ViewBuilder
    private func deadlineToggle(_ label: LocalizedStringKey, icon: String,
                                on: Binding<Bool>, date: Binding<Date>) -> some View {
        FormRow(icon: icon, tint: .accentColor) {
            Toggle(label, isOn: on.animation(.snappy)).font(AppFont.body)
        }
        if on.wrappedValue {
            FormRow(icon: "calendar", tint: .accentColor) {
                DatePicker("vehicle_expires", selection: date, displayedComponents: .date)
                    .font(AppFont.body)
            }
        }
    }

    private func hydrate() {
        guard !didHydrate, let v = editing else { didHydrate = true; return }
        didHydrate = true
        name = v.name
        make = v.make ?? ""; model = v.model ?? ""; plate = v.plate ?? ""
        yearText = v.year.map(String.init) ?? ""
        fuel = v.fuelType ?? "petrol"
        valueText = v.value.map { $0 == $0.rounded() ? String(Int($0)) : String($0) } ?? ""
        if let d = v.itpExpires.flatMap({ AppDate.day(from: $0) }) { itpOn = true; itpDate = d }
        if let d = v.insuranceExpires.flatMap({ AppDate.day(from: $0) }) { insuranceOn = true; insuranceDate = d }
        if let d = v.vignetteExpires.flatMap({ AppDate.day(from: $0) }) { vignetteOn = true; vignetteDate = d }
        notes = v.notes ?? ""
    }

    private func save() {
        isSaving = true
        let payload = VehicleService.VehiclePayload(
            propertyId: nil,
            name: name.trimmingCharacters(in: .whitespaces),
            make: make.isEmpty ? nil : make,
            model: model.isEmpty ? nil : model,
            plate: plate.isEmpty ? nil : plate.uppercased(),
            year: Int(yearText),
            fuelType: fuel,
            value: Double(valueText.replacingOccurrences(of: ",", with: ".")),
            currency: editing?.currency ?? appSettings.preferredCurrency,
            itpExpires: itpOn ? AppDate.dayString(from: itpDate) : nil,
            insuranceExpires: insuranceOn ? AppDate.dayString(from: insuranceDate) : nil,
            vignetteExpires: vignetteOn ? AppDate.dayString(from: vignetteDate) : nil,
            notes: notes.isEmpty ? nil : notes,
            updatedAt: nil)
        Task {
            do {
                if let v = editing {
                    try await service.update(v.id, payload: payload)
                } else {
                    try await service.add(payload)
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}
