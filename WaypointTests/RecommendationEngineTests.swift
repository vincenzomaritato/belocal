import XCTest
@testable import Waypoint

final class RecommendationEngineTests: XCTestCase {
    func testFinalScoreIsClampedToValidRange() async {
        let engine = CoreMLRecommendationEngine(scorerFactory: { nil })

        let profile = UserProfile(
            name: "Test",
            budgetMin: 1000,
            budgetMax: 2500,
            preferredSeasons: ["Spring"],
            travelStyleWeights: ["Culture": 0.6, "Food": 0.4],
            ecoSensitivity: 0.8,
            peopleDefault: 2
        )

        let destination = Destination(
            name: "Sample City",
            country: "Nowhere",
            latitude: 0,
            longitude: 0,
            styles: ["Culture"],
            climate: "Mild",
            costIndex: 0.4,
            ecoScore: 80,
            crowdingIndex: 0.2,
            typicalSeason: ["Spring"],
            distanceKm: 1200
        )

        let recs = await engine.recommendations(
            userProfile: profile,
            destinations: [destination],
            trips: [],
            travelerFeedback: [],
            localInsights: []
        )

        let finalScore = recs.first?.breakdown.finalScore ?? -1
        XCTAssertGreaterThanOrEqual(finalScore, 0)
        XCTAssertLessThanOrEqual(finalScore, 100)
    }

    func testLowerLocalSustainabilityLowersRankingFactor() async {
        let engine = CoreMLRecommendationEngine(scorerFactory: { nil })

        let profile = UserProfile(
            name: "Test",
            budgetMin: 900,
            budgetMax: 4000,
            preferredSeasons: ["Spring", "Autumn"],
            travelStyleWeights: ["Culture": 1.0],
            ecoSensitivity: 0.5,
            peopleDefault: 2
        )

        let highSustainability = Destination(
            name: "Positive",
            country: "A",
            latitude: 0,
            longitude: 0,
            styles: ["Culture"],
            climate: "Mild",
            costIndex: 0.5,
            ecoScore: 70,
            crowdingIndex: 0.4,
            typicalSeason: ["Spring"],
            distanceKm: 1000
        )

        let lowSustainability = Destination(
            name: "Concerned",
            country: "B",
            latitude: 0,
            longitude: 0,
            styles: ["Culture"],
            climate: "Mild",
            costIndex: 0.5,
            ecoScore: 70,
            crowdingIndex: 0.4,
            typicalSeason: ["Spring"],
            distanceKm: 1000
        )

        let recs = await engine.recommendations(
            userProfile: profile,
            destinations: [highSustainability, lowSustainability],
            trips: [],
            travelerFeedback: [],
            localInsights: [
                LocalInsight(destinationId: highSustainability.id, sustainabilityScore: 90, authenticityScore: 70, overcrowdingScore: 30, summaryText: "High"),
                LocalInsight(destinationId: lowSustainability.id, sustainabilityScore: 40, authenticityScore: 70, overcrowdingScore: 30, summaryText: "Low")
            ]
        )

        XCTAssertEqual(recs.first?.destination.name, "Positive")
    }
}
