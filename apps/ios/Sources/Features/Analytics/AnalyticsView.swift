import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(FinancialService.self) private var financialService
    @Environment(TaskService.self) private var taskService
    @Environment(TabBarVisibility.self) private var tabBarVis
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
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.sm)
                                .background(selectedTab == tab ? Color.white : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.xxs)
                .background(Color.primary.opacity(AppOpacity.subtleFill), in: Capsule())
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.lg)

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
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.xxs)
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
