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
                .accessibilityLabel("Add entry")
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
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
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
                            .font(AppFont.caption)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
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
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 48, height: 48)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let change = valueChange, let pct = valueChangePercent {
                    Divider().opacity(0.3)
                    HStack(spacing: 6) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(change >= 0 ? Color(red: 0.15, green: 0.78, blue: 0.4) : .red)
                        Text("\(change >= 0 ? "+" : "")\(formatValue(change, currency: propertyValueService.latestValue?.currency ?? "EUR"))")
                            .font(AppFont.subheadline)
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
                    .font(AppFont.footnoteEmphasis)
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
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.1))
                        AxisValueLabel()
                            .font(.system(size: 10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
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
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xs)

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
                    .foregroundStyle(Color.accentColor)
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
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                        }
                        if let source = entry.source, !source.isEmpty {
                            Text("·").foregroundStyle(Color.primary.opacity(0.2))
                            Text(source)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                                .lineLimit(1)
                        }
                    }

                    if let notes = entry.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
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
                .font(AppFont.title3)
                .foregroundStyle(Color.primary.opacity(0.6))
            Text("Log manual estimates and bank appraisals to see how your property value changes over time.")
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showAdd = true
            } label: {
                Label("Add First Entry", systemImage: "plus")
                    .font(AppFont.subheadline)
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
