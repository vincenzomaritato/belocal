import Foundation

@MainActor
protocol RecommendationEngine {
    func recommendations(
        userProfile: UserProfile,
        destinations: [Destination],
        trips: [Trip],
        travelerFeedback: [TravelerFeedback],
        localInsights: [LocalInsight]
    ) async -> [RecommendationItem]
}
