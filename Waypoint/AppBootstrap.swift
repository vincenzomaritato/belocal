import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class AppBootstrap {
    let settingsStore: AppSettingsStore
    let initialDataService: InitialDataService
    let explainabilityService: any ExplainabilityService
    let coreMLEngine: any RecommendationEngine
    let recommendationNarrativeService: any RecommendationNarrativeServing
    let recommendationQualityReviewService: any RecommendationQualityReviewServing
    let co2Estimator: CO2Estimator
    let localFeedbackAggregator: LocalFeedbackAggregator
    let networkMonitor: NetworkMonitor
    let supabaseSyncService: SupabaseSyncService
    let supabaseAuthService: SupabaseAuthService
    let syncManager: SyncManager
    let toolRouter: ToolRouter
    let liveActivitiesSearch: (SearchInput) async -> [ActivityOption]
    let liveAttractionInfoLookup: @Sendable (String, String?) async -> AttractionCardLiveInfo?
    let travelAPIConfig: TravelAPIConfig
    let openAIChatService: any OpenAIChatServing

    init(settingsStore: AppSettingsStore? = nil) {
        let resolvedSettingsStore = settingsStore ?? AppSettingsStore()
        self.settingsStore = resolvedSettingsStore
        self.initialDataService = InitialDataService()

        let co2Estimator = CO2Estimator()
        self.co2Estimator = co2Estimator

        let explainability = RecommendationExplainabilityService()
        self.explainabilityService = explainability

        self.coreMLEngine = CoreMLRecommendationEngine(
            co2Estimator: co2Estimator,
            explainabilityService: explainability
        )

        self.localFeedbackAggregator = LocalFeedbackAggregator()
        self.networkMonitor = NetworkMonitor()
        let supabaseConfig = SupabaseConfig.load()
        self.supabaseSyncService = SupabaseSyncService(config: supabaseConfig)
        self.supabaseAuthService = SupabaseAuthService(config: supabaseConfig)
        self.syncManager = SyncManager(
            networkMonitor: networkMonitor,
            settingsStore: resolvedSettingsStore,
            supabaseSyncService: supabaseSyncService,
            supabaseAuthService: supabaseAuthService
        )
        let travelConfig = TravelAPIConfig.load()
        self.travelAPIConfig = travelConfig
        let openAIService = OpenAIChatService(config: travelConfig)
        self.openAIChatService = openAIService
        self.recommendationNarrativeService = HybridRecommendationNarrativeService(
            primary: FoundationModelsRecommendationNarrativeService(),
            secondary: OpenAIRecommendationNarrativeService(openAIChatService: openAIService)
        )
        self.recommendationQualityReviewService = HybridRecommendationQualityReviewService(
            primary: FoundationModelsRecommendationQualityReviewService(),
            secondary: OpenAIRecommendationQualityReviewService(openAIChatService: openAIService)
        )

        let liveFlights = LiveFlightsSearchModule()
        let liveRestaurants = LiveRestaurantsSearchModule(config: travelConfig)
        let liveActivities = LiveActivitiesSearchModule(config: travelConfig)
        let liveAttractionInfoService = AttractionCardLiveInfoService(config: travelConfig)
        self.liveActivitiesSearch = { input in await liveActivities.search(input) }
        self.liveAttractionInfoLookup = { attractionName, destination in
            await liveAttractionInfoService.fetch(
                attractionName: attractionName,
                destination: destination
            )
        }

        self.toolRouter = ToolRouter(
            flightsSearch: { input in await liveFlights.search(input) },
            restaurantsSearch: { input in await liveRestaurants.search(input) },
            activitiesSearch: { input in await liveActivities.search(input) }
        )

        Task.detached(priority: .utility) {
            await CityDataset.prewarm()
        }
    }

    func prepare(context: ModelContext) {
        do {
            try initialDataService.prepare(context: context)
        } catch {
            assertionFailure("Initial data setup failed: \(error)")
        }
    }
}
