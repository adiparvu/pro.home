import SwiftUI

@main
struct PRVHouseApp: App {
    @StateObject private var auth = AuthService.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading {
                    SplashView()
                } else if auth.session != nil {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .preferredColorScheme(.dark)
            .environmentObject(auth)
        }
    }
}
