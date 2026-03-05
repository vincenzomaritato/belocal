import Foundation

struct RecommendationExplainabilityService: ExplainabilityService {
    func why(
        destination: Destination,
        breakdown: RecommendationBreakdown,
        userProfile: UserProfile,
        dominantStyle: String
    ) -> String {
        let budgetFit: String = {
            if destination.costIndex <= normalizedBudgetIndex(for: userProfile) {
                return "fits your budget range"
            }
            return "is slightly above your usual budget"
        }()

        let ecoLine: String = {
            if destination.ecoScore >= 80 {
                return "strong sustainability indicators"
            }
            return "balanced sustainability for your profile"
        }()

        let homeDistance = TravelDistanceCalculator.distanceKm(from: userProfile, to: destination)
        let distanceLine: String
        switch homeDistance {
        case ..<1_500:
            distanceLine = "easy to reach from your home base"
        case ..<4_500:
            distanceLine = "a medium-haul option from your home base"
        default:
            distanceLine = "a long-haul option worth planning ahead"
        }

        let style = dominantStyle.lowercased()
        let score = Int(breakdown.finalScore.rounded())
        return "\(destination.name) matches your \(style) style, is \(distanceLine), \(budgetFit), offers \(ecoLine), and reaches an overall \(score)% match."
    }

    private func normalizedBudgetIndex(for profile: UserProfile) -> Double {
        let average = (profile.budgetMin + profile.budgetMax) / 2
        return min(max(average / 5_000, 0), 1)
    }
}
