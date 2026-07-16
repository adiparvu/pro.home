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
        // Secrets that once lived in UserDefaults move to the Keychain at
        // every launch — not lazily when a settings screen happens to open.
        SecretStore.migrateLegacySecrets()
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
                // The color scheme follows the living background's mood
                // (dimineața/zi → light, noaptea → dark; manual pin or Auto
                // from Settings → Aspect → Fundal). Reading `resolved` here
                // is what re-renders the scheme when the mood changes.
                .preferredColorScheme(AppMoodEngine.shared.resolved.palette.colorScheme)
                // In-app text size (Settings → Aspect → Mărimea textului);
                // nil override = pure re-application of the system size.
                .appTextSize()
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
                    // Process quick action from cold launch (stored by AppDelegate
                    // before SwiftUI was ready). The router buffers routes until
                    // MainTabView has mounted, so no launch-time delay is needed.
                    if let quickAction = UserDefaults.standard.string(forKey: "prvio.pendingQuickAction") {
                        UserDefaults.standard.removeObject(forKey: "prvio.pendingQuickAction")
                        router.handle(quickActionType: quickAction)
                    }
                    // Cold-launch deep link (widget/control tap) captured by the
                    // scene delegate before SwiftUI existed.
                    if let pending = UserDefaults.standard.string(forKey: "prvio.pendingDeepLink"),
                       let url = URL(string: pending) {
                        UserDefaults.standard.removeObject(forKey: "prvio.pendingDeepLink")
                        handleExternalURL(url)
                    }
                    // Cold-launch Spotlight/Handoff activity, reduced to what
                    // routing needs (NSUserActivity itself can't be stashed).
                    if let payload = UserDefaults.standard.dictionary(forKey: "prvio.pendingActivity") as? [String: String] {
                        UserDefaults.standard.removeObject(forKey: "prvio.pendingActivity")
                        handlePendingActivity(payload)
                    }
                    // Process App Intent-triggered actions. Flags live in the
                    // app-group suite so intents running in the widget-extension
                    // process reach us too (consumeIntentFlag also drains the
                    // legacy .standard location). Everything funnels through
                    // navigate(to:) so cold-launch intents are buffered too.
                    if SharedDataStore.consumeIntentFlag("prvio.intent.openNewTask") {
                        router.navigate(to: .newTask)
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.openARIA") {
                        router.navigate(to: .aria)
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.openDashboard") {
                        router.navigate(to: .home)
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.showPlants") {
                        router.navigate(to: .plants(id: nil))
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.showChat") {
                        router.navigate(to: .familyChat)
                    }
                    if SharedDataStore.consumeIntentFlag("prvio.intent.showShopping") {
                        // OpenShoppingListIntent opens the LIST, not the add-item
                        // form (matches the quick action in AppRouter).
                        router.navigate(to: .supplies)
                    }
                    // Control Center taps park their destination here because
                    // the OpenURLIntent hand-off has proven unreliable. The
                    // router dedupes when the URL also arrives.
                    if let controlPath = SharedDataStore.consumeControlPath() {
                        let url = URL(string: "prvio://\(controlPath)") ?? URL(string: "prvio://")!
                        router.handle(deepLink: url)
                    }
                case .inactive, .background: lock.willResignActive()
                @unknown default: break
                }
            }
            .onAppear { applyNavBarTint() }
            .onChange(of: appSettings.accentColor) { _, _ in applyNavBarTint() }
            .onChange(of: appSettings.accentEnabled) { _, _ in applyNavBarTint() }
            // The "Automat" accent follows the mood — re-tint the UIKit nav
            // chrome when the atmosphere flips, or back-buttons go stale.
            .onChange(of: AppMoodEngine.shared.resolved) { _, _ in
                if appSettings.accentColor == "auto" { applyNavBarTint() }
            }
            // The custom scene delegate owns URL/activity delivery (it must,
            // to receive Home Screen quick actions) and forwards through these
            // notifications; .onOpenURL stays as a safety net for any path
            // UIKit still routes the SwiftUI way.
            .onOpenURL { url in handleExternalURL(url) }
            .onReceive(NotificationCenter.default.publisher(for: .prvioOpenURL)) { notif in
                if let url = notif.object as? URL {
                    // A notification tap stashes the same URL as a cold-launch
                    // fallback; handling the live post consumes the stash so
                    // it can't replay on a later foreground.
                    if UserDefaults.standard.string(forKey: "prvio.pendingDeepLink") == url.absoluteString {
                        UserDefaults.standard.removeObject(forKey: "prvio.pendingDeepLink")
                    }
                    handleExternalURL(url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .prvioUserActivity)) { notif in
                if let activity = notif.object as? NSUserActivity {
                    router.handle(userActivity: activity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .prvioQuickAction)) { notif in
                if let type = notif.object as? String {
                    // Consume the cold-launch stash too, so the same action
                    // can't replay on the next foreground.
                    UserDefaults.standard.removeObject(forKey: "prvio.pendingQuickAction")
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
            // The MFA gate: accounts with a verified authenticator sign in at
            // AAL1 and stay covered until the 6-digit code (or a one-time
            // backup code) verifies. Re-derived from the REAL assurance level
            // on every session change — never guessed from local state.
            .fullScreenCover(isPresented: Binding(
                get: { auth.session != nil && AccountSecurityService.shared.needsMFAChallenge },
                set: { _ in }
            )) {
                MFAChallengeView()
                    .environment(auth)
                    .interactiveDismissDisabled()
            }
            .task(id: auth.session?.user.id) {
                await AccountSecurityService.shared.refreshMFAStatus()
                // Register this device in the account's session registry once
                // the gate state is known (throttled inside the service).
                if auth.session != nil {
                    await DeviceSessionService.shared.registerCurrentDevice()
                }
            }
            .onContinueUserActivity("com.prvio.task")     { router.handle(userActivity: $0) }
            .onContinueUserActivity("com.prvio.plants")   { router.handle(userActivity: $0) }
            .onContinueUserActivity("com.prvio.chat")     { router.handle(userActivity: $0) }
            .onContinueUserActivity("com.prvio.shopping") { router.handle(userActivity: $0) }
            // Handoff from the watch: whatever page the wrist was reading.
            .onContinueUserActivity("com.prvio.page")     { router.handle(userActivity: $0) }
            .onContinueUserActivity("CSSearchableItemActionType") { router.handle(userActivity: $0) }
        }
    }
}

// MARK: - External entries

extension PRVIOApp {
    /// Magic-link / invite callbacks establish a session; anything else is an
    /// ordinary deep link handled by the router (which buffers routes until
    /// MainTabView has mounted, so cold launches need no delay).
    private func handleExternalURL(_ url: URL) {
        Task {
            if await auth.handleOpenURL(url) { return }
            router.handle(deepLink: url)
        }
    }

    /// Routes the reduced cold-launch activity payload stashed by the scene
    /// delegate (Spotlight result taps, Handoff).
    private func handlePendingActivity(_ payload: [String: String]) {
        if payload["type"] == "CSSearchableItemActionType", let id = payload["spotlightId"] {
            if id.hasPrefix("task-"), let uuid = UUID(uuidString: String(id.dropFirst(5))) {
                router.navigate(to: .tasks(id: uuid))
            } else if id.hasPrefix("plant-"), let uuid = UUID(uuidString: String(id.dropFirst(6))) {
                router.navigate(to: .plants(id: uuid))
            }
            return
        }
        switch payload["tab"] {
        case "tasks": router.navigate(to: .tasks(id: nil))
        case "chat":  router.navigate(to: .chat)
        default: break
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
