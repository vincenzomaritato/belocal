import Foundation

protocol ExplainabilityService {
    func why(
        destination: Destination,
        breakdown: RecommendationBreakdown,
        userProfile: UserProfile,
        dominantStyle: String
    ) -> String
}
