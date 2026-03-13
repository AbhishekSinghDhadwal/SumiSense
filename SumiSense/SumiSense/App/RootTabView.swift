import SwiftUI

struct RootTabView: View {
    @ObservedObject var appState: AppStateViewModel
    @Binding var appTheme: AppTheme
    @Binding var showOnboarding: Bool
    @State private var selectedTab = 0
    @State private var showLaunchBrand = true
    @State private var hasPlayedLaunch = false

    var body: some View {
        ZStack {
            AppBackgroundView()

            TabView(selection: $selectedTab) {
                TodayView(appState: appState)
                    .tag(0)
                    .tabItem {
                        Label("Today", systemImage: "sun.max")
                    }

                TrendsView(appState: appState)
                    .tag(1)
                    .tabItem {
                        Label("Trends", systemImage: "waveform.path.ecg")
                    }

                ShareSafelyView(appState: appState)
                    .tag(2)
                    .tabItem {
                        Label("Share Safely", systemImage: "lock.shield")
                    }

                AboutView(appState: appState, appTheme: $appTheme)
                    .tag(3)
                    .tabItem {
                        Label("About", systemImage: "info.circle")
                    }
            }
            .tint(SumiPalette.accent)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .animation(SumiMotion.gentleSpring, value: selectedTab)

            if showLaunchBrand {
                LaunchBrandView()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .sheet(isPresented: onboardingBinding) {
            OnboardingView {
                showOnboarding = false
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            guard !hasPlayedLaunch else { return }
            hasPlayedLaunch = true
            try? await Task.sleep(for: .milliseconds(1650))
            withAnimation(.easeInOut(duration: 0.42)) {
                showLaunchBrand = false
            }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { showOnboarding && !showLaunchBrand },
            set: { showOnboarding = $0 }
        )
    }
}
