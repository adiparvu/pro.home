import SwiftUI
import Charts
import PhotosUI

// MARK: - Utility meters — section, full page, add sheet
//
// "Contoare & utilități": the monthly index ritual, done right. Per-meter
// cards show the latest index, the honest last-interval consumption and a
// bar chart of monthly deltas; a repeating reminder nudges the submission
// day. Every figure derives from two real readings (see MeterStats).

// MARK: Section (embedded on FinancesView)

struct MetersSection: View {
    @Environment(MeterService.self) private var service

    /// Kinds that have at least one reading, in canonical order.
    private var activeKinds: [MeterKind] {
        MeterKind.allCases.filter { !service.readings(for: $0).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            NavigationLink { MetersView() } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text("meters_title")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            .buttonStyle(.plain)

            NavigationLink { MetersView() } label: {
                if activeKinds.isEmpty {
                    EmptyStateView(icon: "gauge.with.needle",
                                   title: "meters_empty_title",
                                   message: "meters_empty_message")
                } else {
                    HStack(spacing: AppSpacing.md) {
                        ForEach(activeKinds) { kind in
                            meterChip(kind)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.lg)
                    .liquidGlass(cornerRadius: AppRadius.xl)
                }
            }
            .buttonStyle(.plain)
        }
        .task { await service.loadIfNeeded() }
    }

    private func meterChip(_ kind: MeterKind) -> some View {
        let deltas = MeterStats.deltas(for: service.readings(for: kind))
        let lastDelta = deltas.first?.delta
        return VStack(spacing: 4) {
            Image(systemName: kind.icon)
                .font(AppFont.scaled(16, weight: .semibold))
                .foregroundStyle(kind.tint)
            if let d = lastDelta {
                Text(verbatim: "\(Self.compact(d)) \(kind.defaultUnit)")
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            } else {
                Text(verbatim: "–")
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(Color.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity)
    }

    static func compact(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: Full page

struct MetersView: View {
    @Environment(MeterService.self) private var service

    @State private var showAdd = false
    @State private var presetKind: MeterKind = .electricity

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                ForEach(MeterKind.allCases) { kind in
                    MeterCard(kind: kind) {
                        presetKind = kind
                        showAdd = true
                    }
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("meters_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presetKind = .electricity
                    showAdd = true
                    HapticFeedback.impact(.medium)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(Text("meter_add_reading"))
            }
        }
        .sheet(isPresented: $showAdd) { AddMeterReadingSheet(kind: presetKind) }
        .task { await service.loadIfNeeded() }
        .refreshable { await service.load() }
    }
}

// MARK: One meter card

struct MeterCard: View {
    @Environment(MeterService.self) private var service
    let kind: MeterKind
    let onAdd: () -> Void

    @State private var showHistory = false

    var body: some View {
        let readings = service.readings(for: kind)
        let deltas = MeterStats.deltas(for: readings)
        let points = MeterStats.monthlyConsumption(for: readings)

        VStack(alignment: .leading, spacing: AppSpacing.base) {
            header(latest: deltas.first)

            if !points.isEmpty {
                chart(points)
            }

            if readings.isEmpty {
                Text("meter_no_readings")
                    .font(AppFont.scaled(13))
                    .foregroundStyle(Color.secondaryTextColor)
            } else if showHistory {
                historyList(deltas)
            }

            HStack {
                Button {
                    HapticFeedback.impact(.light)
                    onAdd()
                } label: {
                    Label("meter_add_reading", systemImage: "plus.circle.fill")
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(kind.tint)
                }
                .buttonStyle(.plain)

                Spacer()

                if !readings.isEmpty {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { showHistory.toggle() }
                        HapticFeedback.selection()
                    } label: {
                        Text(showHistory ? "meter_hide_history" : "meter_show_history")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    .buttonStyle(.plain)
                }

                reminderMenu
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private func header(latest: (reading: MeterReading, delta: Double?)?) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                    .fill(kind.tint.opacity(AppOpacity.tintedFill))
                Image(systemName: kind.icon)
                    .font(AppFont.scaled(17, weight: .semibold))
                    .foregroundStyle(kind.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(kind.label)
                    .font(AppFont.scaled(16, weight: .bold))
                    .foregroundStyle(.primary)
                if let latest {
                    Text(String(format: String(localized: "meter_last_index_fmt"),
                                MetersSection.compact(latest.reading.reading),
                                latest.reading.unitDisplay,
                                latest.reading.date.map { AppDate.monthDay.string(from: $0) } ?? latest.reading.readingDate))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            Spacer()
            if let delta = latest?.delta {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: MetersSection.compact(delta))
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(kind.tint)
                        .monospacedDigit()
                    Text(verbatim: kind.defaultUnit)
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
        }
    }

    private func chart(_ points: [MeterStats.MonthPoint]) -> some View {
        Chart(points) { p in
            BarMark(x: .value("Month", p.label),
                    y: .value("Consumption", p.consumption),
                    width: .ratio(0.45))
                .foregroundStyle(kind.tint.opacity(0.85))
                .cornerRadius(3)
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel().font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
        }
        .frame(height: 110)
        .accessibilityLabel(Text(kind.label))
    }

    private func historyList(_ deltas: [(reading: MeterReading, delta: Double?)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(deltas.prefix(12)), id: \.reading.id) { item in
                HStack(spacing: AppSpacing.sm) {
                    Text(verbatim: item.reading.date.map { AppDate.monthDayYear.string(from: $0) } ?? item.reading.readingDate)
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.primary)
                    if item.reading.photoUrl != nil {
                        Image(systemName: "camera.fill")
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Spacer()
                    if let d = item.delta {
                        Text(verbatim: "+\(MetersSection.compact(d))")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(kind.tint)
                            .monospacedDigit()
                    }
                    Text(verbatim: MetersSection.compact(item.reading.reading))
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .padding(.vertical, AppSpacing.xs)
                .contextMenu {
                    Button(role: .destructive) {
                        Task { await service.deleteReading(item.reading) }
                    } label: {
                        Label("meter_delete_reading", systemImage: "trash")
                    }
                }
                if item.reading.id != deltas.prefix(12).last?.reading.id {
                    Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5)
                }
            }
        }
    }

    /// Monthly "send the index" reminder — a compact menu on the card foot.
    private var reminderMenu: some View {
        let current = service.reminderDay(for: kind)
        return Menu {
            Picker("meter_reminder", selection: Binding(
                get: { current },
                set: { service.setReminderDay($0, for: kind); HapticFeedback.selection() }
            )) {
                Text("meter_reminder_off").tag(0)
                ForEach([1, 5, 10, 15, 20, 25, 28], id: \.self) { d in
                    Text(String(format: String(localized: "goal_auto_day_fmt"), d)).tag(d)
                }
            }
        } label: {
            Image(systemName: current > 0 ? "bell.badge.fill" : "bell")
                .font(AppFont.scaled(14, weight: .semibold))
                .foregroundStyle(current > 0 ? kind.tint : Color.secondaryTextColor)
                .frame(width: 30, height: 30)
        }
        .accessibilityLabel(Text("meter_reminder"))
    }
}

// MARK: Add reading sheet

struct AddMeterReadingSheet: View {
    @Environment(MeterService.self) private var service
    @Environment(\.dismiss) private var dismiss

    @State var kind: MeterKind
    @State private var value = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool { Double(value.replacingOccurrences(of: ",", with: ".")) != nil }

    var body: some View {
        FormScaffold(title: "meter_add_reading", canSave: canSave,
                     isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: kind.icon, tint: kind.tint) {
                    Picker("meter_kind", selection: $kind) {
                        ForEach(MeterKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "gauge.with.needle", tint: kind.tint) {
                    Text("meter_index").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $value).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(AppFont.scaled(20, weight: .semibold))
                    Text(verbatim: kind.defaultUnit).foregroundStyle(Color.secondaryTextColor)
                }
                FormDivider()
                FormRow(icon: "calendar", tint: kind.tint) {
                    DatePicker("meter_date", selection: $date, displayedComponents: .date)
                        .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "text.alignleft", tint: kind.tint) {
                    TextField("meter_note_placeholder", text: $note).font(AppFont.body)
                }
            }

            FormGroup {
                FormRow(icon: "camera.fill", tint: kind.tint) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        HStack {
                            Text(photoData == nil ? "meter_add_photo" : "meter_photo_attached")
                                .font(AppFont.body)
                                .foregroundStyle(photoData == nil ? Color.accentColor : .primary)
                            Spacer()
                            if photoData != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.brandSuccess)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { photoData = try? await item.loadTransferable(type: Data.self) }
        }
    }

    private func save() {
        guard let v = Double(value.replacingOccurrences(of: ",", with: ".")) else { return }
        isSaving = true
        Task {
            do {
                try await service.addReading(kind: kind, value: v, date: date,
                                             note: note, photoData: photoData)
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}
