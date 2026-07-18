import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(FinancialService.self) private var financialService
    @Environment(TaskService.self) private var taskService
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
                }
                .refreshable {
                    await financialService.load()
                    await taskService.load()
                }
            }
        }
        .navigationTitle("Analytics")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Export lives in the existing report builder — one PDF pipeline
            // for the whole app, never a duplicate exporter per screen. The
            // report view reads its services from this stack's environment.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PropertyReportView()
                } label: {
                    Image(systemName: "doc.richtext")
                        .font(AppFont.headline)
                }
                .accessibilityLabel("Raport")
            }
        }
        .floatingSpeedDial(.analytics)
    }
}
