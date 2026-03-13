import SwiftUI

@main
struct SumiSenseApp: App {
    @StateObject private var appState = AppStateViewModel()
    @AppStorage("sumi_has_seen_onboarding") private var hasSeenOnboarding = false
    @AppStorage("sumi_app_theme") private var appThemeRawValue = AppTheme.system.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(
                appState: appState,
                appTheme: Binding(
                    get: { selectedTheme },
                    set: { appThemeRawValue = $0.rawValue }
                ),
                showOnboarding: Binding(
                    get: { !hasSeenOnboarding },
                    set: { newValue in
                        if newValue == false {
                            hasSeenOnboarding = true
                        }
                    }
                )
            )
            .preferredColorScheme(selectedTheme.colorScheme)
        }
    }
}
