import SwiftData
import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable {
        case home
        case explore
        case planner
    }

    private enum EntryStage: Equatable {
        case login
        case onboarding
        case welcome
        case main
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppBootstrap.self) private var bootstrap

    @State private var homeViewModel = HomeViewModel()
    @State private var cityExplorerViewModel = CityExplorerViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var entryStage: EntryStage = .login
    @State private var selectedTab: Tab = .home
    @State private var plannerLaunchRequest: PlannerLaunchRequest?
    @State private var isSettingsPresented = false

    var body: some View {
        Group {
            switch entryStage {
            case .login:
                LoginView {
                    refreshEntryStage()
                }
            case .onboarding:
                OnboardingFlowView(homeViewModel: homeViewModel) {
                    refreshEntryStage()
                }
            case .welcome:
                PostOnboardingWelcomeView(homeViewModel: homeViewModel) {
                    refreshEntryStage()
                }
            case .main:
                mainTabView
            }
        }
        .animation(.easeInOut(duration: 0.25), value: entryStage)
        .task {
            bootstrap.prepare(context: modelContext)
            homeViewModel.load(context: modelContext, bootstrap: bootstrap)
            settingsViewModel.load(from: homeViewModel.userProfile)
            refreshEntryStage()
            await bootstrap.syncManager.processPendingOperations(context: modelContext)
        }
        .onChange(of: bootstrap.networkMonitor.isOnline) { _, _ in
            Task {
                await bootstrap.syncManager.processPendingOperations(context: modelContext)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshEntryStage()
            Task {
                await bootstrap.syncManager.processPendingOperations(context: modelContext)
            }
        }
        .onChange(of: bootstrap.settingsStore.isAuthenticated) { _, _ in
            refreshEntryStage()
        }
    }

    private func refreshEntryStage() {
        if !bootstrap.settingsStore.isAuthenticated {
            entryStage = .login
            return
        }

        if !bootstrap.settingsStore.hasCompletedOnboarding {
            entryStage = .onboarding
            return
        }

        if !bootstrap.settingsStore.hasSeenOnboardingWelcome {
            entryStage = .welcome
            return
        }

        entryStage = .main
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                homeViewModel: homeViewModel,
                onPlannerSuggestionTap: { recommendation in
                    let prefill = PlannerSuggestionPrefill(recommendation: recommendation)
                    plannerLaunchRequest = PlannerLaunchRequest(prefill: prefill)
                    selectedTab = .planner
                },
                onProfileTap: {
                    isSettingsPresented = true
                }
            )
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(Tab.home)

            CityExplorerView(
                homeViewModel: homeViewModel,
                viewModel: cityExplorerViewModel,
                onProfileTap: {
                    isSettingsPresented = true
                }
            )
                .tabItem {
                    Label("Explore", systemImage: "map")
                }
                .tag(Tab.explore)

            PlannerView(
                homeViewModel: homeViewModel,
                launchRequest: plannerLaunchRequest,
                onProfileTap: {
                    isSettingsPresented = true
                }
            )
                .tabItem {
                    Label("Planner", systemImage: "sparkles.rectangle.stack")
                }
                .tag(Tab.planner)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                homeViewModel: homeViewModel,
                settingsViewModel: settingsViewModel
            )
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.roottab") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)

    return RootTabView()
        .environment(bootstrap)
        .modelContainer(SwiftDataStack.makeContainer(inMemory: true))
}
