import Foundation

struct PlannerSuggestionPrefill: Equatable {
    let destination: String
    let country: String
    let estimatedBudget: Int
    let interests: [String]
    let ecoScore: Int
    let reason: String
    let suggestedDays: Int

    init(recommendation: RecommendationItem) {
        destination = recommendation.destination.name
        country = recommendation.destination.country
        let rawBudget = 900 + Int((recommendation.destination.costIndex * 3_600).rounded())
        estimatedBudget = max(700, rawBudget)
        interests = Array(recommendation.destination.styles.map(PlaceCanonicalizer.canonicalStyle).prefix(3))
        ecoScore = recommendation.ecoScore
        reason = recommendation.whyRecommended
        suggestedDays = max(3, min(10, Int((recommendation.destination.distanceKm / 1_500.0).rounded()) + 3))
    }

    var destinationLabel: String {
        "\(destination), \(country)"
    }

    var interestsLabel: String {
        if interests.isEmpty {
            return L10n.tr("Culture + Food")
        }
        return interests.map(L10n.style).joined(separator: " + ")
    }

    var budgetLabel: String {
        L10n.f("Comfort ~%d EUR", estimatedBudget)
    }

    var plannerPrompt: String {
        """
        I want to plan this trip:
        - Destination: \(destinationLabel)
        - Interests: \(interestsLabel)
        - Budget: \(budgetLabel)
        - Suggested trip length: \(suggestedDays) days
        - Estimated eco score: \(ecoScore)
        Suggested reason: \(reason)
        """
    }
}

struct PlannerLaunchRequest: Equatable, Identifiable {
    let id: UUID
    let prefill: PlannerSuggestionPrefill
    let prompt: String

    init(prefill: PlannerSuggestionPrefill) {
        self.id = UUID()
        self.prefill = prefill
        self.prompt = prefill.plannerPrompt
    }
}
