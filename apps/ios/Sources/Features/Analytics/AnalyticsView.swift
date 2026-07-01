import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject private var financialService: FinancialService
    @EnvironmentObject private var taskService: TaskService
    @EnvironmentObject private var tabBarVis: TabBarVisibility
    @State private var selectedTab: AnalyticsTab = .finances
    @State private var displayedMonth: Date = Calendar.current.startOfMonth(Date())

    enum AnalyticsTab: String, CaseIterable {
        case finances = "Finances"
        case tasks    = "Tasks"
        case forecast = "Forecast"

        var displayName: String {
            switch self {
            case .finances: return String(localized: "Finances")
            case .tasks:    return String(localized: "Tasks")
            case .forecast: return String(localized: "Forecast")
            }
        }
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(AnalyticsTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.spring(response: 0.3)) { selectedTab = tab }
                        } label: {
                            Text(tab.displayName)
                                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                                .foregroundStyle(selectedTab == tab ? Color.black : Color.primary.opacity(0.55))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? Color.white : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case .finances:
                            FinancesSection(service: financialService, displayedMonth: $displayedMonth)
                        case .tasks:
                            TasksSection(service: taskService)
                        case .forecast:
                            ForecastSection(financialService: financialService)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 110)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("analyticsScroll")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "analyticsScroll")
                .onPreferenceChange(ScrollOffsetKey.self) { y in
                    tabBarVis.scrollOffset = y
                }
                .refreshable {
                    await financialService.load()
                    await taskService.load()
                }
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.large)
        .floatingSpeedDial(.analytics)
    }
}
