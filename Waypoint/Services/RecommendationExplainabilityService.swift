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
                return L10n.tr("fits your budget range")
            }
            return L10n.tr("is slightly above your usual budget")
        }()

        let ecoLine: String = {
            if destination.ecoScore >= 80 {
                return L10n.tr("strong sustainability indicators")
            }
            return L10n.tr("balanced sustainability for your profile")
        }()

        let homeDistance = TravelDistanceCalculator.distanceKm(from: userProfile, to: destination)
        let distanceLine: String
        switch homeDistance {
        case ..<1_500:
            distanceLine = L10n.tr("easy to reach from your home base")
        case ..<4_500:
            distanceLine = L10n.tr("a medium-haul option from your home base")
        default:
            distanceLine = L10n.tr("a long-haul option worth planning ahead")
        }

        let style = L10n.style(dominantStyle).lowercased()
        let score = Int(breakdown.finalScore.rounded())
        return L10n.f("%@ matches your %@ style, is %@, %@, offers %@, and reaches an overall %d%% match.", destination.name, style, distanceLine, budgetFit, ecoLine, score)
    }

    private func normalizedBudgetIndex(for profile: UserProfile) -> Double {
        let average = (profile.budgetMin + profile.budgetMax) / 2
        return min(max(average / 5_000, 0), 1)
    }
}
