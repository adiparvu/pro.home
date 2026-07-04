import SwiftUI

@main
struct PRVIOApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var auth        = AuthService.shared
    @State private var appSettings = AppSettings()
    @State private var lock        = AppLockManager()
    @State private var router      = AppRouter()
    @State private var iconManager = IconManager()
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
                            .environment(appSettings)
                            .environment(router)
                            .environment(iconManager)
                            .environment(\.appLanguage, appSettings.currentLanguage)
                    } else {
                        LoginView()
                    }
                }
                .preferredColorScheme(appSettings.resolvedColorScheme)
                .tint(appSettings.accentEnabled ? avatarRingColor(for: appSettings.accentColor) : .blue)
                .environment(\.locale, appSettings.appLocale)
                .environment(auth)
                .environment(lock)

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
            .background(IconColorSchemeWatcher(iconManager: iconManager))
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    lock.didBecomeActive()
                    NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
                    // Process quick action from cold launch (stored by AppDelegate before SwiftUI was ready).
                    // Defer so MainTabView has mounted — an immediate tab/sheet change on
                    // cold launch is overridden by the initial mount (same reason the
                    // Finances quick action delays its tab switch), so the shortcut
                    // appeared to "do nothing".
                    if let quickAction = UserDefaults.standard.string(forKey: "prvio.pendingQuickAction") {
                        UserDefaults.standard.removeObject(forKey: "prvio.pendingQuickAction")
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(500))
                            router.handle(quickActionType: quickAction)
                        }
                    }
                    // Process App Intent-triggered actions. Flags live in the
                    // app-group suite so intents running in the widget-extension
                    // process reach us too (consumeIntentFlag also drains the
                    // legacy .standard location).
                    if SharedDataStore.consumeIntentFlag("prvio.intent.openNewTask") {
                        router.showAddTask = true
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.openARIA") {
                        router.showARIA = true
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.openDashboard") {
                        router.selectedTab = .home
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.showPlants") {
                        router.showWaterPlant = true
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.showChat") {
                        router.showFamilyChat = true
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.showShopping") {
                        // OpenShoppingListIntent opens the LIST, not the add-item
                        // form (matches the quick action in AppRouter).
                        router.selectedTab = .settings
                        router.showSuppliesView = true
                    }
                case .inactive, .background: lock.willResignActive()
                @unknown default: break
                }
            }
            .onAppear { applyNavBarTint() }
            .onChange(of: appSettings.accentColor) { _, _ in applyNavBarTint() }
            .onChange(of: appSettings.accentEnabled) { _, _ in applyNavBarTint() }
            .onOpenURL { url in
                // Magic-link / invite callbacks establish a session; anything
                // else is an ordinary deep link handled by the router.
                Task {
                    if await auth.handleOpenURL(url) { return }
                    router.handle(deepLink: url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .prvioQuickAction)) { notif in
                if let type = notif.object as? String {
                    router.handle(quickActionType: type)
                }
            }
            // Invited accounts must set a strong password on first sign-in.
            .fullScreenCover(isPresented: Binding(
                get: { auth.needsPasswordSetup },
                set: { _ in }
            )) {
                ForcePasswordView()
                    .environment(auth)
                    .interactiveDismissDisabled()
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
        // The appearance proxy only tints nav bars created AFTER this point, so
        // changing the accent left every on-screen back button its old color.
        // Update the live bars too so the accent applies instantly everywhere.
        UINavigationBar.appearance().tintColor = c
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for window in ws.windows {
                window.tintColor = c
                applyTint(c, in: window.rootViewController)
            }
        }
    }

    private func applyTint(_ c: UIColor, in vc: UIViewController?) {
        guard let vc else { return }
        if let nav = vc as? UINavigationController {
            nav.navigationBar.tintColor = c
        }
        vc.children.forEach { applyTint(c, in: $0) }
        applyTint(c, in: vc.presentedViewController)
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
