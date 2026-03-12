import SwiftData
import SwiftUI

struct RootTabView: View {
    enum Tab: Hashable {
        case home
        case explore
        case planner
    }

    private enum EntryStage: Equatable {
        case launching
        case login
        case onboarding
        case welcome
        case main
    }

    private enum EntryStageDirection {
        case forward
        case backward
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppBootstrap.self) private var bootstrap

    @State private var homeViewModel = HomeViewModel()
    @State private var cityExplorerViewModel = CityExplorerViewModel()
    @State private var settingsViewModel = SettingsViewModel()
    @State private var entryStage: EntryStage = .launching
    @State private var previousEntryStage: EntryStage = .launching
    @State private var entryStageDirection: EntryStageDirection = .forward
    @State private var selectedTab: Tab = .home
    @State private var plannerLaunchRequest: PlannerLaunchRequest?
    @State private var isSettingsPresented = false
    @State private var hasResolvedLaunchFlow = false
    @State private var hasStartedLaunchFlow = false

    var body: some View {
        ZStack {
            entryStageView
                .id(entryStage)
                .transition(entryStageTransition)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.9), value: entryStage)
        .task {
            guard !hasStartedLaunchFlow else { return }
            hasStartedLaunchFlow = true
            await runLaunchFlow()
        }
        .onChange(of: bootstrap.networkMonitor.isOnline) { _, isOnline in
            guard isOnline, bootstrap.settingsStore.isAuthenticated else { return }
            Task {
                await reloadAppState()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshEntryStage()
            guard bootstrap.settingsStore.isAuthenticated else { return }
            Task {
                await reloadAppState()
            }
        }
        .onChange(of: bootstrap.settingsStore.isAuthenticated) { _, isAuthenticated in
            refreshEntryStage()
            Task {
                if isAuthenticated {
                    await reloadAppState(forceDownsync: true)
                } else {
                    resetSignedOutState()
                }
            }
        }
    }

    @ViewBuilder
    private var entryStageView: some View {
        switch entryStage {
        case .launching:
            AppLaunchIntroView(isReturningUser: bootstrap.settingsStore.isAuthenticated)
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

    private var entryStageTransition: AnyTransition {
        if previousEntryStage == .launching || entryStage == .launching {
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.985)),
                removal: .opacity
            )
        }

        switch entryStageDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }

    private func refreshEntryStage() {
        guard hasResolvedLaunchFlow || entryStage != .launching else {
            return
        }

        let nextStage: EntryStage

        if !bootstrap.settingsStore.isAuthenticated {
            nextStage = .login
        } else if !bootstrap.settingsStore.hasCompletedOnboarding {
            nextStage = .onboarding
        } else if !bootstrap.settingsStore.hasSeenOnboardingWelcome {
            nextStage = .welcome
        } else {
            nextStage = .main
        }

        guard nextStage != entryStage else {
            return
        }

        previousEntryStage = entryStage
        entryStageDirection = stageIndex(for: nextStage) >= stageIndex(for: entryStage) ? .forward : .backward

        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            entryStage = nextStage
        }
    }

    private func stageIndex(for stage: EntryStage) -> Int {
        switch stage {
        case .launching:
            return -1
        case .login:
            return 0
        case .onboarding:
            return 1
        case .welcome:
            return 2
        case .main:
            return 3
        }
    }

    private func runLaunchFlow() async {
        async let appReload: Void = reloadAppState(forceDownsync: bootstrap.settingsStore.isAuthenticated)
        try? await Task.sleep(for: .milliseconds(1100))
        _ = await appReload

        hasResolvedLaunchFlow = true
        refreshEntryStage()
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
                Label(L10n.tr("Home"), systemImage: "house.fill")
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
                    Label(L10n.tr("Explore"), systemImage: "map")
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
                    Label(L10n.tr("Planner"), systemImage: "sparkles.rectangle.stack")
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

    private func reloadAppState(forceDownsync: Bool = false) async {
        if bootstrap.settingsStore.isAuthenticated {
            homeViewModel.load(context: modelContext, bootstrap: bootstrap)
            if homeViewModel.userProfile == nil {
                bootstrap.prepare(context: modelContext)
                homeViewModel.load(context: modelContext, bootstrap: bootstrap)
            }
            queueProfileSyncIfNeeded()
            await bootstrap.syncManager.processPendingOperations(
                context: modelContext,
                forceDownsync: forceDownsync
            )
            homeViewModel.load(context: modelContext, bootstrap: bootstrap)
            settingsViewModel.load(from: homeViewModel.userProfile)
        } else {
            resetSignedOutState()
        }
    }

    private func queueProfileSyncIfNeeded() {
        guard bootstrap.supabaseSyncService.config.isConfigured else { return }
        guard let profile = homeViewModel.userProfile else { return }

        let authUserID = bootstrap.settingsStore.authenticatedUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authUserID.isEmpty else { return }

        let descriptor = FetchDescriptor<SyncOperation>(sortBy: [SortDescriptor(\SyncOperation.createdAt)])
        let operations = (try? modelContext.fetch(descriptor)) ?? []
        let hasQueuedProfileUpsert = operations.contains { operation in
            guard operation.type == .upsertProfile else { return false }
            guard
                let data = operation.payloadJSON.data(using: .utf8),
                let payload = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                return false
            }
            return payload["profileId"] == profile.id.uuidString && operation.status != .synced
        }

        guard !hasQueuedProfileUpsert else { return }

        bootstrap.syncManager.enqueue(
            type: .upsertProfile,
            payload: [
                "profileId": profile.id.uuidString,
                "authUserId": authUserID,
                "name": profile.name,
                "budgetMin": String(format: "%.0f", profile.budgetMin),
                "budgetMax": String(format: "%.0f", profile.budgetMax),
                "ecoSensitivity": String(format: "%.3f", profile.ecoSensitivity),
                "peopleDefault": "\(profile.peopleDefault)",
                "homeLatitude": String(format: "%.6f", profile.homeLatitude),
                "homeLongitude": String(format: "%.6f", profile.homeLongitude),
                "homeCity": profile.homeCity,
                "homeCountry": profile.homeCountry,
                "preferredSeasons": profile.preferredSeasons.sorted().joined(separator: ","),
                "travelStyleWeightsJSON": profile.travelStyleWeightsJSON,
                "updatedAt": ISO8601DateFormatter().string(from: .now)
            ],
            context: modelContext
        )
    }

    private func resetSignedOutState() {
        do {
            try bootstrap.initialDataService.clearLocalData(
                context: modelContext,
                recreateProfile: false
            )
        } catch {
            assertionFailure("Signed-out cleanup failed: \(error)")
        }
        homeViewModel.clearCachedData()
        cityExplorerViewModel.resetState()
        settingsViewModel.resetState()
        plannerLaunchRequest = nil
        selectedTab = .home
        isSettingsPresented = false
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
