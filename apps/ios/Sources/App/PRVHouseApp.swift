import SwiftUI

@main
struct PRVHouseApp: App {
    @StateObject private var auth        = AuthService.shared
    @StateObject private var appSettings = AppSettings()

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
            .environment(\.locale, Locale(identifier: appSettings.locale))
            .environmentObject(auth)
        }
    }
}
