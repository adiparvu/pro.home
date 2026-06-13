import SwiftUI

enum AppTab: String, CaseIterable {
    case home, map, tasks, analytics, assistant, settings

    var icon: String {
        switch self {
        case .home:      return "house.fill"
        case .map:       return "map.fill"
        case .tasks:     return "checklist"
        case .analytics: return "chart.bar.xaxis"
        case .assistant: return "sparkles"
        case .settings:  return "gearshape.fill"
        }
    }

    var label: String {
        switch self {
        case .home:      return "Home"
        case .map:       return "Hartă"
        case .tasks:     return "Tasks"
        case .analytics: return "Analytics"
        case .assistant: return "Assistant"
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
    @StateObject private var familyService = FamilyService()
    @StateObject private var messageService = MessageService()
    @StateObject private var currencyService = CurrencyService()
    @StateObject private var elementService = PropertyElementService()
    @AppStorage("prvio.onboarding.done") private var onboardingDone = false
    @State private var selectedTab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selected: $selectedTab, overdueCount: taskService.overdueCount)
                .padding(.horizontal, 20)
                .padding(.bottom, safeAreaBottom > 0 ? safeAreaBottom - 6 : 14)
                .padding(.top, 4)
        }
        .environmentObject(taskService)
        .environmentObject(propertyService)
        .environmentObject(profileService)
        .environmentObject(financialService)
        .environmentObject(documentService)
        .environmentObject(notificationScheduler)
        .environmentObject(budgetService)
        .environmentObject(familyService)
        .environmentObject(messageService)
        .environmentObject(currencyService)
        .environmentObject(elementService)
        .fullScreenCover(isPresented: .constant(!onboardingDone)) {
            OnboardingView()
                .environmentObject(propertyService)
                .environmentObject(auth)
        }
        .task {
            await currencyService.refresh()
            await propertyService.load()
            await taskService.load()
            await financialService.load()
            await documentService.load()
            await familyService.load()
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
            if let propId = propertyService.primary?.id {
                await messageService.load(propertyId: propId)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            NavigationStack { DashboardView(selectedTab: $selectedTab) }
        case .map:
            NavigationStack { PropertyMapView() }
        case .tasks:
            NavigationStack { TasksView() }
        case .analytics:
            NavigationStack { AnalyticsView() }
        case .assistant:
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
    @Namespace private var tabNS

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases.filter { $0 != .assistant }, id: \.self) { tab in
                FloatingTabItem(
                    tab: tab,
                    isSelected: selected == tab,
                    badge: tab == .tasks ? overdueCount : 0,
                    namespace: tabNS
                ) {
                    HapticFeedback.selection()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.68)) {
                        selected = tab
                    }
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 9)
        .liquidGlass(cornerRadius: 34, thick: true)
        .shadow(color: Color.primary.opacity(0.12), radius: 28, y: 10)
        .shadow(color: Color.primary.opacity(0.04), radius: 4,  y: 1)
    }
}

struct FloatingTabItem: View {
    let tab: AppTab
    let isSelected: Bool
    var badge: Int = 0
    let namespace: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .matchedGeometryEffect(id: "tabPill", in: namespace)
                        .shadow(color: Color.primary.opacity(0.08), radius: 6, y: 2)
                }
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : Color.primary.opacity(0.38))
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text("\(min(badge, 9))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(.red, in: Circle())
                                .offset(x: 8, y: -8)
                        }
                    }
            }
            .frame(width: 52, height: 40)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
