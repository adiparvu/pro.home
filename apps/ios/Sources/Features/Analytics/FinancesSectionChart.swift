import SwiftUI
import Charts

extension FinancesSection {

    // MARK: - Range Chart Data

    var rangeChartData: [(label: String, income: Double, expenses: Double)] {
        let iso = DateFormatter(); iso.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        let now = Date()

        func parseDate(_ r: FinancialRecord) -> Date? { iso.date(from: r.date) }

        func dayBuckets(days: Int) -> [(String, Double, Double)] {
            let lbl = DateFormatter(); lbl.dateFormat = days <= 7 ? "EEE" : "d"
            return (0..<days).reversed().compactMap { offset in
                guard let day = cal.date(byAdding: .day, value: -offset, to: now),
                      let start = cal.dateInterval(of: .day, for: day)?.start,
                      let end = cal.dateInterval(of: .day, for: day)?.end else { return nil }
                let recs = service.records.filter { r in
                    guard let d = parseDate(r) else { return false }
                    return d >= start && d < end
                }
                return (lbl.string(from: day),
                        recs.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount },
                        recs.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount })
            }
        }

        func monthBuckets(from start: Date, to end: Date) -> [(String, Double, Double)] {
            let monthCount = (cal.dateComponents([.month], from: start, to: end).month ?? 0) + 1
            let lbl = DateFormatter(); lbl.dateFormat = monthCount > 8 ? "MMM yy" : "MMM"
            var buckets: [(String, Double, Double)] = []
            var cursor = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
            while cursor <= end {
                guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
                let recs = service.records.filter { r in
                    guard let d = parseDate(r) else { return false }
                    return d >= cursor && d < next
                }
                buckets.append((lbl.string(from: cursor),
                                recs.filter { $0.type == "income" }.reduce(0) { $0 + $1.amount },
                                recs.filter { $0.type == "expense" }.reduce(0) { $0 + $1.amount }))
                cursor = next
            }
            return buckets
        }

        switch chartRange {
        case .day:
            return dayBuckets(days: 1)
        case .week:
            return dayBuckets(days: 7)
        case .month:
            return dayBuckets(days: 30)
        case .threeMonths:
            let start = cal.date(byAdding: .month, value: -3, to: now) ?? now
            return monthBuckets(from: start, to: now)
        case .sixMonths:
            let start = cal.date(byAdding: .month, value: -6, to: now) ?? now
            return monthBuckets(from: start, to: now)
        case .year:
            let start = cal.date(byAdding: .year, value: -1, to: now) ?? now
            return monthBuckets(from: start, to: now)
        case .custom:
            return monthBuckets(from: customStart, to: customEnd)
        }
    }

    // MARK: - Range Chips

    var rangeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ChartRange.allCases, id: \.self) { r in
                    Button {
                        if r == .custom {
                            showCustomSheet = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.18)) { chartRange = r }
                        }
                    } label: {
                        Text(LocalizedStringKey(r.rawValue))
                            .font(.system(size: 12, weight: chartRange == r ? .semibold : .regular))
                            .foregroundStyle(chartRange == r ? .white : Color.primary.opacity(0.6))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(chartRange == r ? Color.accentColor : Color.primary.opacity(AppOpacity.subtleFill),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chart Card

    var chartCard: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Monthly evolution")
                    .font(AppFont.subheadline)

                rangeChips

                let data = rangeChartData
                let hasData = data.contains { $0.income > 0 || $0.expenses > 0 }

                if !hasData {
                    emptyChartPlaceholder
                } else {
                    Chart {
                        ForEach(data, id: \.label) { item in
                            AreaMark(
                                x: .value("Period", item.label),
                                y: .value("Income", item.income)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.18),
                                             Color(red: 0.3, green: 0.85, blue: 0.5).opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Period", item.label),
                                y: .value("Income", item.income)
                            )
                            .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.5))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                            .symbol(Circle().strokeBorder(lineWidth: 1.5))
                            .symbolSize(24)

                            AreaMark(
                                x: .value("Period", item.label),
                                y: .value("Expenses", item.expenses)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.12), Color.red.opacity(0.01)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Period", item.label),
                                y: .value("Expenses", item.expenses)
                            )
                            .foregroundStyle(.red.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                                .foregroundStyle(Color.primary.opacity(0.05))
                            AxisValueLabel().foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel().foregroundStyle(.secondary)
                                .font(.system(size: 10))
                        }
                    }
                    .frame(height: 160)
                    .animation(.easeInOut(duration: 0.25), value: chartRange)
                }

                HStack(spacing: 16) {
                    legendItem(color: Color(red: 0.3, green: 0.85, blue: 0.5), label: "Income", solid: true)
                    legendItem(color: .red.opacity(0.75), label: "Expenses", solid: false)
                }
            }
        }
        .sheet(isPresented: $showCustomSheet) {
            NavigationStack {
                Form {
                    Section("Range") {
                        DatePicker("From", selection: $customStart, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd,
                                   in: customStart..., displayedComponents: .date)
                    }
                }
                .navigationTitle("Custom range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCustomSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            withAnimation(.easeInOut(duration: 0.18)) { chartRange = .custom }
                            showCustomSheet = false
                        }
                        .font(AppFont.subheadline)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Helpers

    var emptyChartPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 28))
                .foregroundStyle(Color.primary.opacity(0.15))
            Text("Add transactions to see the chart")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    func legendItem(color: Color, label: LocalizedStringKey, solid: Bool) -> some View {
        HStack(spacing: 6) {
            if solid {
                Circle().fill(color).frame(width: 8, height: 8)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 4, height: 2)
                    }
                }
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
