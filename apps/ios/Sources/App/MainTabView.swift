import SwiftUI

struct MainTabView: View {
    @State private var selected: Tab = .home

    enum Tab: String, CaseIterable {
        case home, tasks, analytics, aria, settings

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .tasks: return "checkmark.circle.fill"
            case .analytics: return "chart.xyaxis.line"
            case .aria: return "sparkles"
            case .settings: return "gearshape.fill"
            }
        }

        var label: String {
            switch self {
            case .home: return "Home"
            case .tasks: return "Tasks"
            case .analytics: return "Analytics"
            case .aria: return "ARIA"
            case .settings: return "Settings"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selected) {
                DashboardView()
                    .tag(Tab.home)

                TasksView()
                    .tag(Tab.tasks)

                AnalyticsView()
                    .tag(Tab.analytics)

                ARIAView()
                    .tag(Tab.aria)

                SettingsView()
                    .tag(Tab.settings)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom tab bar
            CustomTabBar(selected: $selected)
        }
        .ignoresSafeArea(edges: .bottom)
        .preferredColorScheme(.dark)
    }
}

private struct CustomTabBar: View {
    @Binding var selected: MainTabView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.Tab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selected = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: tab == .aria ? 22 : 20, weight: .semibold))
                            .frame(width: 44, height: 32)
                            .background(
                                selected == tab
                                ? .white.opacity(0.12)
                                : .clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .scaleEffect(selected == tab ? 1.05 : 1.0)

                        Text(tab.label)
                            .font(.system(size: 10, weight: selected == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selected == tab ? .white : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }
}
