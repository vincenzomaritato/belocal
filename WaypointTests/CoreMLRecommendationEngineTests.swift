import XCTest
@testable import Waypoint

final class CoreMLRecommendationEngineTests: XCTestCase {
    func testFallsBackWhenModelScorerIsUnavailable() async {
        let destination = makeDestination(name: "Fallback City", ecoScore: 72)

        let engine = CoreMLRecommendationEngine(
            scorerFactory: { nil }
        )

        let recommendations = await engine.recommendations(
            userProfile: makeProfile(),
            destinations: [destination],
            trips: [],
            travelerFeedback: [],
            localInsights: []
        )

        XCTAssertEqual(recommendations.count, 1)
        XCTAssertEqual(recommendations.first?.destination.name, "Fallback City")
        XCTAssertGreaterThanOrEqual(recommendations.first?.breakdown.finalScore ?? 0, 0)
        XCTAssertLessThanOrEqual(recommendations.first?.breakdown.finalScore ?? 101, 100)
    }

    func testScorerInfluencesRankingWhenAvailable() async {
        let ecoHigh = makeDestination(name: "Eco High", ecoScore: 92)
        let ecoLow = makeDestination(name: "Eco Low", ecoScore: 45)

        let engine = CoreMLRecommendationEngine(
            scorerFactory: { EcoPriorityScorer() }
        )

        let recommendations = await engine.recommendations(
            userProfile: makeProfile(),
            destinations: [ecoLow, ecoHigh],
            trips: [],
            travelerFeedback: [],
            localInsights: []
        )

        XCTAssertEqual(recommendations.first?.destination.name, "Eco High")
        XCTAssertGreaterThanOrEqual(recommendations.first?.breakdown.finalScore ?? 0, 0)
        XCTAssertLessThanOrEqual(recommendations.first?.breakdown.finalScore ?? 101, 100)
    }

    private func makeProfile() -> UserProfile {
        UserProfile(
            name: "Test",
            budgetMin: 1000,
            budgetMax: 2800,
            preferredSeasons: ["Spring", "Summer"],
            travelStyleWeights: ["Culture": 0.6, "Nature": 0.4],
            ecoSensitivity: 0.7,
            peopleDefault: 2
        )
    }

    private func makeDestination(name: String, ecoScore: Double) -> Destination {
        Destination(
            name: name,
            country: "Testland",
            latitude: 0,
            longitude: 0,
            styles: ["Culture", "Nature"],
            climate: "Warm",
            costIndex: 0.5,
            ecoScore: ecoScore,
            crowdingIndex: 0.35,
            typicalSeason: ["Spring", "Summer"],
            distanceKm: 1200
        )
    }
}

private struct EcoPriorityScorer: CoreMLDestinationScoring {
    func score(_ features: CoreMLRecommendationFeatures) -> Double? {
        // Deterministic scorer used in tests.
        return features.ecoScore
    }
}
