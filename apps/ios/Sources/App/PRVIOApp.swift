import SwiftUI

@main
struct PRVIOApp: App {
    @StateObject private var auth        = AuthService.shared
    @StateObject private var appSettings = AppSettings()

    init() {
        applyGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading {
                    SplashView()
                } else if auth.session != nil {
                    MainTabView()
                        .environmentObject(appSettings)
                } else {
                    LoginView()
                }
            }
            .preferredColorScheme(appSettings.resolvedColorScheme)
            .tint(avatarRingColor(for: appSettings.accentColor))
            .environment(\.locale, Locale(identifier: appSettings.locale))
            .environmentObject(auth)
        }
    }
}

// MARK: - iOS 26/27 global appearance

private func applyGlobalAppearance() {
    // Navigation bar — transparent glass (liquid glass style)
    let nav = UINavigationBarAppearance()
    nav.configureWithTransparentBackground()
    nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
    nav.shadowColor = .clear
    UINavigationBar.appearance().standardAppearance = nav
    UINavigationBar.appearance().scrollEdgeAppearance = nav
    UINavigationBar.appearance().compactAppearance = nav

    // System tab bar hidden — we use custom floating bar
    UITabBar.appearance().isHidden = true
}
