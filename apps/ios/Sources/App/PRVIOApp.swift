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
            .tint(appSettings.accentEnabled ? avatarRingColor(for: appSettings.accentColor) : .blue)
            .environment(\.locale, Locale(identifier: appSettings.locale))
            .environmentObject(auth)
        }
    }
}

// MARK: - Global appearance

private func applyGlobalAppearance() {
    if #available(iOS 26, *) {
        // iOS 26+ — navigation bar uses Liquid Glass automatically.
        // Resetting to default lets the system apply its native glass treatment.
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    } else {
        // iOS 17–25 — use system blur material, which adapts to dark/light mode,
        // reduceTransparency, and increaseContrast automatically via UIKit.
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }

}
