import SwiftUI
import Charts

// MARK: - PropertyValueView

struct PropertyValueView: View {
    @EnvironmentObject private var propertyValueService: PropertyValueService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var currencyService: CurrencyService
    @EnvironmentObject private var appSettings: AppSettings

    @State private var showAdd = false

    private var entries: [PropertyValueEntry] { propertyValueService.sortedEntries }

    private var latestValue: Double? { propertyValueService.latestValue?.valueAmount }

    private var firstValue: Double? { entries.first?.valueAmount }

    private var valueChange: Double? {
        guard let latest = latestValue, let first = firstValue, entries.count > 1 else { return nil }
        return latest - first
    }

    private var valueChangePercent: Double? {
        guard let change = valueChange, let first = firstValue, first > 0 else { return nil }
        return (change / first) * 100
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            if propertyValueService.entries.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Property Value")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPropertyValueSheet()
                .environmentObject(propertyValueService)
                .environmentObject(propertyService)
                .environmentObject(currencyService)
        }
        .task {
            if let id = propertyService.primary?.id {
                await propertyValueService.load(propertyId: id)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                heroCard
                if entries.count >= 2 {
                    chartCard
                }
                entriesList
                Spacer(minLength: 110)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await propertyValueService.load(propertyId: id)
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Value")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .tracking(0.3)

                        if let latest = latestValue {
                            Text(formatValue(latest, currency: propertyValueService.latestValue?.currency ?? "EUR"))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                        }
                    }
                    Spacer()
                    Image(systemName: "house.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let change = valueChange, let pct = valueChangePercent {
                    Divider().opacity(0.3)
                    HStack(spacing: 6) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(change >= 0 ? Color(red: 0.15, green: 0.78, blue: 0.4) : .red)
                        Text("\(change >= 0 ? "+" : "")\(formatValue(change, currency: propertyValueService.latestValue?.currency ?? "EUR"))")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(change >= 0 ? Color(red: 0.15, green: 0.78, blue: 0.4) : .red)
                        Text("(\(change >= 0 ? "+" : "")\(String(format: "%.1f", pct))%)")
                            .font(.system(size: 13))
                            .foregroundStyle(change >= 0 ? Color(red: 0.15, green: 0.78, blue: 0.4).opacity(0.75) : .red.opacity(0.75))
                        Text("since first entry")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.4))
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Value Over Time")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.6))

                Chart {
                    ForEach(entries) { entry in
                        if let date = entry.enteredDate {
                            LineMark(
                                x: .value("Date", date),
                                y: .value("Value", entry.valueAmount)
                            )
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.catmullRom)

                            PointMark(
                                x: .value("Date", date),
                                y: .value("Value", entry.valueAmount)
                            )
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(40)

                            AreaMark(
                                x: .value("Date", date),
                                y: .value("Value", entry.valueAmount)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.1))
                        AxisValueLabel()
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.1))
                        AxisValueLabel()
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
                .frame(height: 180)
                .tint(.accentColor)
            }
        }
    }

    // MARK: - Entries List

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HISTORY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            LazyVStack(spacing: 10) {
                ForEach(entries.reversed()) { entry in
                    entryRow(entry)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                HapticFeedback.warning()
                                Task { await propertyValueService.delete(entry) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func entryRow(_ entry: PropertyValueEntry) -> some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(formatValue(entry.valueAmount, currency: entry.currency))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        if let date = entry.enteredDate {
                            Text(Self.dateFormatter.string(from: date))
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.45))
                        }
                        if let source = entry.source, !source.isEmpty {
                            Text("·").foregroundStyle(Color.primary.opacity(0.2))
                            Text(source)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(0.45))
                                .lineLimit(1)
                        }
                    }

                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 52))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("Track your property value")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Log manual estimates and bank appraisals to see how your property value changes over time.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.35))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add First Entry", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    private func formatValue(_ amount: Double, currency: String) -> String {
        let symbol: String
        switch currency {
        case "EUR": symbol = "€"
        case "RON": symbol = "RON "
        case "USD": symbol = "$"
        case "GBP": symbol = "£"
        default: symbol = currency + " "
        }
        if amount >= 1_000_000 {
            return "\(symbol)\(String(format: "%.2f", amount / 1_000_000))M"
        } else if amount >= 1_000 {
            return "\(symbol)\(String(format: "%.0f", amount))"
        }
        return "\(symbol)\(String(format: "%.2f", amount))"
    }
}

// MARK: - AddPropertyValueSheet

private struct AddPropertyValueSheet: View {
    @EnvironmentObject private var propertyValueService: PropertyValueService
    @EnvironmentObject private var propertyService: PropertyService
    @EnvironmentObject private var currencyService: CurrencyService
    @Environment(\.dismiss) private var dismiss

    @State private var valueText = ""
    @State private var currency = "EUR"
    @State private var source = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false

    private let currencies = ["EUR", "RON", "USD", "GBP"]
    private let commonSources = ["Manual estimate", "Bank appraisal", "Real estate agent", "Online estimate", "Official valuation"]

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        formSection("Value") {
                            HStack(spacing: 10) {
                                Image(systemName: "banknote.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.accentColor)
                                    .frame(width: 28)
                                TextField("0", text: $valueText)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .tint(.accentColor)
                                    .keyboardType(.decimalPad)
                                Spacer()
                                Picker("Currency", selection: $currency) {
                                    ForEach(currencies, id: \.self) { c in
                                        Text(c).tag(c)
                                    }
                                }
                                .tint(.accentColor)
                                .pickerStyle(.menu)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }

                        formSection("Details") {
                            sourcePicker
                            divider
                            DatePicker(
                                "Date",
                                selection: $date,
                                displayedComponents: .date
                            )
                            .tint(.accentColor)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }

                        formSection("Notes") {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "note.text")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.accentColor)
                                    .frame(width: 28)
                                    .padding(.top, 2)
                                TextField("Optional notes…", text: $notes, axis: .vertical)
                                    .font(.system(size: 15))
                                    .foregroundStyle(.primary)
                                    .tint(.accentColor)
                                    .lineLimit(3...6)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Add Value Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.7))
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().tint(.accentColor)
                    } else {
                        Button("Save") { Task { await save() } }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.accentColor)
                            .disabled((Double(valueText) ?? 0) <= 0 || isSaving)
                    }
                }
            }
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.accentColor)
                    .frame(width: 28)
                TextField("Source (e.g. Bank appraisal)", text: $source)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            if source.isEmpty {
                Divider().opacity(0.3).padding(.leading, 52)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(commonSources, id: \.self) { s in
                            Button {
                                source = s
                                HapticFeedback.impact(.light)
                            } label: {
                                Text(s)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.primary.opacity(0.7))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.07), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func formSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }

    private func save() async {
        guard let amount = Double(valueText), amount > 0,
              let propertyId = propertyService.primary?.id else { return }
        isSaving = true
        defer { isSaving = false }
        let payload = NewPropertyValuePayload(
            propertyId: propertyId,
            valueAmount: amount,
            currency: currency,
            source: source.isEmpty ? nil : source,
            notes: notes.isEmpty ? nil : notes,
            enteredAt: ISO8601DateFormatter().string(from: date)
        )
        try? await propertyValueService.add(payload)
        HapticFeedback.success()
        dismiss()
    }
}
