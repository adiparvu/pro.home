import SwiftUI

enum AppTab: String, CaseIterable {
    case home, tasks, analytics, aria, settings

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .tasks:     return "checklist"
        case .analytics: return "chart.bar.xaxis"
        case .aria:      return "sparkles"
        case .settings:  return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .home:      return "Home"
        case .tasks:     return "Tasks"
        case .analytics: return "Analytics"
        case .aria:      return "ARIA"
        case .settings:  return "Settings"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appSettings: AppSettings
    @StateObject private var taskService = TaskService()
    @StateObject private var propertyService = PropertyService()
    @StateObject private var profileService = ProfileService()
    @StateObject private var financialService = FinancialService()
    @StateObject private var documentService = DocumentService()
    @StateObject private var notificationScheduler = NotificationScheduler()
    @StateObject private var budgetService = BudgetService()
    @AppStorage("prvhouse.onboarding.done") private var onboardingDone = false
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            FloatingTabBar(selected: $selectedTab, overdueCount: taskService.overdueCount)
                .padding(.horizontal, 20)
                .padding(.bottom, safeAreaBottom > 0 ? safeAreaBottom - 6 : 14)
        }
        .ignoresSafeArea(edges: .bottom)
        .environmentObject(taskService)
        .environmentObject(propertyService)
        .environmentObject(profileService)
        .environmentObject(financialService)
        .environmentObject(documentService)
        .environmentObject(notificationScheduler)
        .environmentObject(budgetService)
        .fullScreenCover(isPresented: .constant(!onboardingDone)) {
            OnboardingView()
                .environmentObject(propertyService)
                .environmentObject(auth)
        }
        .task {
            await propertyService.load()
            await taskService.load()
            await financialService.load()
            await documentService.load()
            if let uid = auth.session?.user.id {
                await profileService.load(userId: uid)
                if let profile = profileService.profile {
                    appSettings.loadFromProfile(profile)
                }
            }
            await notificationScheduler.reschedule(
                tasks: taskService.tasks,
                documents: documentService.documents
            )
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            NavigationStack { DashboardView() }
        case .tasks:
            NavigationStack { TasksView() }
        case .analytics:
            NavigationStack { AnalyticsView() }
        case .aria:
            NavigationStack { ARIAView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }

    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom) ?? 0
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selected: AppTab
    var overdueCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                FloatingTabItem(
                    tab: tab,
                    isSelected: selected == tab,
                    badge: tab == .tasks ? overdueCount : 0
                ) {
                    HapticFeedback.selection()
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        selected = tab
                    }
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.8
                        )
                )
        }
        .shadow(color: .black.opacity(0.45), radius: 32, y: 12)
    }
}

struct FloatingTabItem: View {
    let tab: AppTab
    let isSelected: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(isSelected ? 0.16 : 0))
                        .frame(height: 36)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

                    Image(systemName: tab.icon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.38))
                        .symbolEffect(.bounce, value: isSelected)
                        .frame(height: 36)

                    if badge > 0 {
                        Text("\(min(badge, 9))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(.red, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
                .frame(height: 36)

                Text(tab.label)
                    .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.38))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
