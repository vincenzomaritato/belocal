import Foundation

struct RecommendationBreakdown: Hashable {
    var matchScore: Double
    var environmentalPenalty: Double
    var localApprovalFactor: Double
    var finalScore: Double
}

struct RecommendationItem: Identifiable {
    var id: UUID { destination.id }
    let destination: Destination
    let matchScore: Int
    let ecoScore: Int
    let estimatedCO2: Double
    let whyRecommended: String
    let breakdown: RecommendationBreakdown
}
