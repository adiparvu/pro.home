import SwiftUI
import Charts

// MARK: - FeedingSystemView
//
// Schedules management + manual feed log + weekly consumption chart.
// Receives FeedingService and FishService as @ObservedObject (shared from PondDashboardView).

struct FeedingSystemView: View {
    let pond: Pond
    @ObservedObject var feedingService: FeedingService
    @ObservedObject var fishService: FishService
    @State private var selectedTab: FeedingTab = .schedules
    @State private var showAddSchedule = false
    @State private var showManualFeed = false

    enum FeedingTab: String, CaseIterable {
        case schedules = "Schedules"
        case log       = "Log"
        case analysis  = "Analysis"
    }

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

            VStack(spacing: 0) {
                tabPicker
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        switch selectedTab {
                        case .schedules: schedulesContent
                        case .log:       logContent
                        case .analysis:  analysisContent
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(pond.name + " — Feeding")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showManualFeed = true
                    } label: {
                        Label("Feed Now", systemImage: "hand.tap.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: "#FF9F0A"))
                    }

                    if selectedTab == .schedules {
                        Button {
                            showAddSchedule = true
                        } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSchedule) {
            AddFeedingScheduleSheet(pond: pond, feedingService: feedingService)
        }
        .sheet(isPresented: $showManualFeed) {
            ManualFeedSheet(pond: pond, feedingService: feedingService)
        }
        .task {
            try? await feedingService.loadSchedules(for: pond.id)
            try? await feedingService.loadRecentLogs(for: pond.id)
        }
    }

    // MARK: Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(FeedingTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? .white : .white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selectedTab == tab
                                ? RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.12))
                                : nil
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .padding(.bottom, 16)
    }

    // MARK: Schedules

    private var schedulesContent: some View {
        VStack(spacing: 12) {
            if feedingService.schedules.isEmpty {
                emptyState(
                    icon: "calendar.badge.clock",
                    title: "No schedules",
                    subtitle: "Create a schedule to automate feedings."
                )
            } else {
                nextFeedingBanner

                ForEach(feedingService.schedules) { schedule in
                    ScheduleRow(schedule: schedule) {
                        Task { try? await feedingService.toggleSchedule(schedule) }
                    } onDelete: {
                        Task { try? await feedingService.deleteSchedule(schedule) }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 4)
    }

    private var nextFeedingBanner: some View {
        let next = feedingService.schedules
            .filter { $0.isActive }
            .sorted { timeValue($0) < timeValue($1) }
            .first

        return Group {
            if let schedule = next {
                HStack(spacing: 14) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(hex: "#FF9F0A"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next Feeding")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(schedule.name + " · " + formattedTime(schedule.hour, schedule.minute))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Text(String(format: "%.0f g", schedule.amountGrams))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: "#FF9F0A"))
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(hex: "#FF9F0A").opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(hex: "#FF9F0A").opacity(0.2), lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 20)
            }
        }
    }

    private func timeValue(_ s: FeedingSchedule) -> Int { s.hour * 60 + s.minute }
    private func formattedTime(_ h: Int, _ m: Int) -> String {
        String(format: "%02d:%02d", h, m)
    }

    // MARK: Log

    private var logContent: some View {
        VStack(spacing: 12) {
            if feedingService.recentLogs.isEmpty {
                emptyState(
                    icon: "list.bullet.clipboard",
                    title: "No feeding logs",
                    subtitle: "Feed manually or enable a schedule to generate logs."
                )
            } else {
                ForEach(feedingService.recentLogs) { log in
                    FeedingLogRow(log: log)
                        .padding(.horizontal, 20)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Analysis

    private var analysisContent: some View {
        VStack(spacing: 16) {
            weeklyStatsCard
            consumptionChart
            biomassRatioCard
        }
        .padding(.top, 4)
    }

    private var weeklyStatsCard: some View {
        HStack(spacing: 0) {
            statItem(
                value: String(format: "%.0f g", feedingService.weeklyFoodConsumptionGrams()),
                label: "Weekly",
                color: Color(hex: "#FF9F0A")
            )
            Divider().frame(width: 0.5, height: 40).background(Color.white.opacity(0.12))
            statItem(
                value: String(format: "%.0f g", feedingService.weeklyFoodConsumptionGrams() / 7),
                label: "Daily avg",
                color: Color(hex: "#30D158")
            )
            Divider().frame(width: 0.5, height: 40).background(Color.white.opacity(0.12))
            statItem(
                value: "\(feedingService.recentLogs.count)",
                label: "Feedings",
                color: Color(hex: "#0A84FF")
            )
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }

    private func statItem(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }

    private var consumptionChart: some View {
        let groupedByDay = Dictionary(grouping: feedingService.recentLogs) {
            Calendar.current.startOfDay(for: $0.fedAt)
        }
        let last7 = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
            .map { Calendar.current.startOfDay(for: $0) }
            .reversed()
        let dailyAmounts: [(Date, Double)] = last7.map { day in
            let total = groupedByDay[day]?.reduce(0) { $0 + $1.amountGrams } ?? 0
            return (day, total)
        }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Daily Consumption (7D)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            Chart {
                ForEach(dailyAmounts, id: \.0) { day, amount in
                    BarMark(
                        x: .value("Day", day, unit: .day),
                        y: .value("Grams", amount)
                    )
                    .foregroundStyle(Color(hex: "#FF9F0A").opacity(0.8))
                    .cornerRadius(4)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .chartYAxis {
                AxisMarks {
                    AxisGridLine(stroke: StrokeStyle(dash: [2, 4]))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }

    private var biomassRatioCard: some View {
        let biomass = fishService.estimatedBiomassKg()
        let weeklyGrams = feedingService.weeklyFoodConsumptionGrams()
        let dailyRatio = biomass > 0 ? (weeklyGrams / 7) / (biomass * 1000) * 100 : 0

        return VStack(alignment: .leading, spacing: 8) {
            Text("Feeding Rate")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)

            HStack {
                Text(String(format: "%.2f%%", dailyRatio))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(feedingRateColor(dailyRatio))
                Text("of body weight / day")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 8)
            }

            Text("Optimal for koi: 1–3% body weight per day. Adjust seasonally based on water temperature.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(feedingRateColor(dailyRatio).opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(feedingRateColor(dailyRatio).opacity(0.2), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 20)
    }

    private func feedingRateColor(_ rate: Double) -> Color {
        if rate == 0 { return Color(hex: "#636366") }
        if rate < 0.5 { return Color(hex: "#FF3B30") }
        if rate > 4 { return Color(hex: "#FF9F0A") }
        return Color(hex: "#30D158")
    }

    // MARK: Empty State

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.white.opacity(0.2))
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }
}

// MARK: - ScheduleRow

private struct ScheduleRow: View {
    let schedule: FeedingSchedule
    var onToggle: () -> Void
    var onDelete: () -> Void

    private var dayLabel: String {
        if schedule.daysOfWeek.isEmpty { return "Every day" }
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return schedule.daysOfWeek.compactMap { $0 >= 1 && $0 <= 7 ? names[$0 - 1] : nil }.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(schedule.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 8) {
                    Text(String(format: "%02d:%02d", schedule.hour, schedule.minute))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "#FF9F0A"))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                    Text(schedule.foodType.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                    Text(String(format: "%.0f g", schedule.amountGrams))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Text(dayLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            Toggle("", isOn: .constant(schedule.isActive))
                .toggleStyle(SwitchToggleStyle(tint: Color(hex: "#FF9F0A")))
                .labelsHidden()
                .onTapGesture { onToggle() }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - FeedingLogRow

private struct FeedingLogRow: View {
    let log: FeedingLog

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FF9F0A").opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: log.foodType.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#FF9F0A"))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(log.foodType.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)

                    if log.source == .automatic {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }

                Text(String(format: "%.0f g · %@", log.amountGrams, log.fedAt.relativeFormatted))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Spacer()

            Text(log.source == .manual ? "Manual" : log.source == .automatic ? "Auto" : "ARIA")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.07)))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

// MARK: - AddFeedingScheduleSheet

struct AddFeedingScheduleSheet: View {
    let pond: Pond
    @ObservedObject var feedingService: FeedingService
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Morning Feed"
    @State private var hour = 8
    @State private var minute = 0
    @State private var foodType: FoodType = .pellet
    @State private var amountGrams = 50.0
    @State private var selectedDays: Set<Int> = []
    @State private var haEntityId = ""
    @State private var isSaving = false

    private let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        sectionField("Name") {
                            TextField("Schedule name", text: $name)
                                .fieldStyle()
                        }

                        sectionField("Time") {
                            HStack {
                                Picker("Hour", selection: $hour) {
                                    ForEach(0..<24, id: \.self) { h in
                                        Text(String(format: "%02d", h)).tag(h)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 100)

                                Text(":")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)

                                Picker("Minute", selection: $minute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { m in
                                        Text(String(format: "%02d", m)).tag(m)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(height: 100)
                            }
                            .colorScheme(.dark)
                        }

                        sectionField("Food Type") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(FoodType.allCases, id: \.self) { type in
                                        foodTypeChip(type)
                                    }
                                }
                            }
                        }

                        sectionField("Amount: \(Int(amountGrams)) g") {
                            Slider(value: $amountGrams, in: 10...500, step: 10)
                                .tint(Color(hex: "#FF9F0A"))
                        }

                        sectionField("Days (empty = every day)") {
                            HStack(spacing: 8) {
                                ForEach(1...7, id: \.self) { day in
                                    dayChip(day: day, name: dayNames[day - 1])
                                }
                            }
                        }

                        sectionField("HA Feeder Entity (optional)") {
                            TextField("switch.auto_feeder", text: $haEntityId)
                                .fieldStyle()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("New Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.6))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .foregroundStyle(name.isEmpty ? .white.opacity(0.3) : Color(hex: "#FF9F0A"))
                        .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            content()
        }
    }

    private func foodTypeChip(_ type: FoodType) -> some View {
        let isSelected = foodType == type
        return Button {
            foodType = type
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 11))
                Text(type.displayName)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isSelected ? Color(hex: "#FF9F0A") : .white.opacity(0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color(hex: "#FF9F0A").opacity(0.15) : Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(isSelected ? Color(hex: "#FF9F0A").opacity(0.4) : Color.clear, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func dayChip(day: Int, name: String) -> some View {
        let isSelected = selectedDays.contains(day)
        return Button {
            if isSelected { selectedDays.remove(day) } else { selectedDays.insert(day) }
        } label: {
            Text(name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: "#FF9F0A") : .white.opacity(0.45))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isSelected ? Color(hex: "#FF9F0A").opacity(0.15) : Color.white.opacity(0.06))
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? Color(hex: "#FF9F0A").opacity(0.4) : Color.clear, lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func save() {
        isSaving = true
        Task {
            let schedule = FeedingSchedule(
                pondId: pond.id,
                name: name,
                hour: hour,
                minute: minute,
                foodType: foodType,
                amountGrams: amountGrams,
                isActive: true,
                daysOfWeek: Array(selectedDays).sorted(),
                haFeederEntityId: haEntityId.isEmpty ? nil : haEntityId
            )
            try? await feedingService.addSchedule(schedule)
            dismiss()
        }
    }
}

// MARK: - ManualFeedSheet

struct ManualFeedSheet: View {
    let pond: Pond
    @ObservedObject var feedingService: FeedingService
    @Environment(\.dismiss) private var dismiss

    @State private var foodType: FoodType = .pellet
    @State private var amountGrams = 50.0
    @State private var notes = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.04, green: 0.04, blue: 0.08).ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("Food Type")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(FoodType.allCases, id: \.self) { type in
                                let isSelected = foodType == type
                                Button { foodType = type } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: type.icon).font(.system(size: 13))
                                        Text(type.displayName).font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundStyle(isSelected ? Color(hex: "#FF9F0A") : .white.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(isSelected ? Color(hex: "#FF9F0A").opacity(0.12) : Color.white.opacity(0.05))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Amount: \(Int(amountGrams)) g")
                        Slider(value: $amountGrams, in: 10...500, step: 10).tint(Color(hex: "#FF9F0A"))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("Notes (optional)")
                        TextField("Observations…", text: $notes)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .tint(.white)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }

                    Spacer()

                    Button {
                        isSaving = true
                        Task {
                            try? await feedingService.logManualFeeding(
                                pondId: pond.id,
                                foodType: foodType,
                                amountGrams: amountGrams,
                                notes: notes.isEmpty ? nil : notes
                            )
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "hand.tap.fill")
                            Text("Feed Now — \(Int(amountGrams)) g")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(hex: "#FF9F0A"))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                }
                .padding(20)
            }
            .navigationTitle("Feed Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
    }
}

// MARK: - TextField style helper (local)

private extension View {
    func fieldStyle() -> some View {
        self
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
            )
    }
}
