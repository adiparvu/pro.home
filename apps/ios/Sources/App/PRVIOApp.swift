import SwiftUI

@main
struct PRVIOApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var auth        = AuthService.shared
    @StateObject private var appSettings = AppSettings()
    @StateObject private var lock        = AppLockManager()
    @StateObject private var router      = AppRouter()
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
                            .environmentObject(router)
                    } else {
                        LoginView()
                    }
                }
                .id(appSettings.appLocale.identifier)
                .preferredColorScheme(appSettings.resolvedColorScheme)
                .tint(appSettings.accentEnabled ? avatarRingColor(for: appSettings.accentColor) : .blue)
                .environment(\.locale, appSettings.appLocale)
                .environmentObject(auth)
                .environmentObject(lock)

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
                case .active:
                    lock.didBecomeActive()
                    NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
                    // Process quick action from cold launch (stored by AppDelegate before SwiftUI was ready)
                    if let quickAction = UserDefaults.standard.string(forKey: "prvio.pendingQuickAction") {
                        UserDefaults.standard.removeObject(forKey: "prvio.pendingQuickAction")
                        router.handle(quickActionType: quickAction)
                    }
                    // Process App Intent-triggered actions
                    if UserDefaults.standard.bool(forKey: "prvio.intent.openNewTask") {
                        UserDefaults.standard.removeObject(forKey: "prvio.intent.openNewTask")
                        router.showAddTask = true
                    }
                    if UserDefaults.standard.bool(forKey: "prvio.intent.showPlants") {
                        UserDefaults.standard.removeObject(forKey: "prvio.intent.showPlants")
                        router.showWaterPlant = true
                    }
                    if UserDefaults.standard.bool(forKey: "prvio.intent.showChat") {
                        UserDefaults.standard.removeObject(forKey: "prvio.intent.showChat")
                        router.selectedTab = .chat
                    }
                    if UserDefaults.standard.bool(forKey: "prvio.intent.showShopping") {
                        UserDefaults.standard.removeObject(forKey: "prvio.intent.showShopping")
                        router.showAddSupply = true
                    }
                case .inactive, .background: lock.willResignActive()
                @unknown default: break
                }
            }
            .onAppear { applyNavBarTint() }
            .onChange(of: appSettings.accentColor) { _, _ in applyNavBarTint() }
            .onChange(of: appSettings.accentEnabled) { _, _ in applyNavBarTint() }
            .onOpenURL { url in
                router.handle(deepLink: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .prvioQuickAction)) { notif in
                if let type = notif.object as? String {
                    router.handle(quickActionType: type)
                }
            }
            .onContinueUserActivity("com.prvio.task")     { router.handle(userActivity: $0) }
            .onContinueUserActivity("com.prvio.plants")   { router.handle(userActivity: $0) }
            .onContinueUserActivity("com.prvio.chat")     { router.handle(userActivity: $0) }
            .onContinueUserActivity("com.prvio.shopping") { router.handle(userActivity: $0) }
            .onContinueUserActivity("CSSearchableItemActionType") { router.handle(userActivity: $0) }
        }
    }
}

// MARK: - Accent tint for UIKit back button

extension PRVIOApp {
    func applyNavBarTint() {
        let c: UIColor = appSettings.accentEnabled
            ? UIColor(avatarRingColor(for: appSettings.accentColor))
            : .systemBlue
        UINavigationBar.appearance().tintColor = c
    }
}

// MARK: - Global appearance

private func applyGlobalAppearance() {
    if #available(iOS 26, *) {
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    } else {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
    // Apply accent tint immediately from UserDefaults (appSettings not yet initialized in init)
    let accentEnabled = UserDefaults.standard.bool(forKey: "prvio.accentOn")
    let accentName = UserDefaults.standard.string(forKey: "prvio.accentColor") ?? "blue"
    let tint: UIColor = accentEnabled ? UIColor(avatarRingColor(for: accentName)) : .systemBlue
    UINavigationBar.appearance().tintColor = tint
}
