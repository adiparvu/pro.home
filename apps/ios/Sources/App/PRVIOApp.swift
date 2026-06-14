import SwiftUI

@main
struct PRVIOApp: App {
    @StateObject private var auth        = AuthService.shared
    @StateObject private var appSettings = AppSettings()
    @StateObject private var lock        = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        applyGlobalAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
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
                .environmentObject(lock)

                // App lock (only when signed in)
                if auth.session != nil {
                    if lock.isLocked {
                        LockScreenView(manager: lock)
                            .transition(.opacity)
                            .zIndex(10)
                    } else if lock.privacyCover {
                        PrivacyCoverView()
                            .transition(.opacity)
                            .zIndex(9)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
            .onAppear { lock.appDidLaunch() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:               lock.didBecomeActive()
                case .inactive, .background: lock.willResignActive()
                @unknown default: break
                }
            }
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
