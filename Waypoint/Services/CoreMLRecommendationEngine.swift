import CoreML
import Foundation

protocol CoreMLDestinationScoring {
    func score(_ features: CoreMLRecommendationFeatures) -> Double?
}

struct CoreMLRecommendationFeatures {
    let budgetCenter: Double
    let destinationCost: Double
    let seasonMatch: Double
    let styleMatch: Double
    let ecoScore: Double
    let climateMatch: Double
    let normalizedCO2: Double
    let crowdingEffect: Double
    let localSustainability: Double

    let preferenceScore: Double
    let environmentalPenalty: Double
    let localApprovalFactor: Double
}

private struct RecommendationBehaviorSignals {
    let styleAffinity: [String: Double]
    let countryAffinity: [String: Double]
    let climateAffinity: [String: Double]
    let preferredDistanceKm: Double
    let visitedCountryKeys: Set<String>
}

struct CoreMLRecommendationEngine: RecommendationEngine {
    let co2Estimator: CO2Estimator
    let explainabilityService: any ExplainabilityService

    private let scorerFactory: () -> (any CoreMLDestinationScoring)?

    init(
        co2Estimator: CO2Estimator = CO2Estimator(),
        explainabilityService: any ExplainabilityService = RecommendationExplainabilityService(),
        scorerFactory: @escaping () -> (any CoreMLDestinationScoring)? = { BundleCoreMLDestinationScorer() }
    ) {
        self.co2Estimator = co2Estimator
        self.explainabilityService = explainabilityService
        self.scorerFactory = scorerFactory
    }

    func recommendations(
        userProfile: UserProfile,
        destinations: [Destination],
        trips: [Trip],
        travelerFeedback: [TravelerFeedback],
        localInsights: [LocalInsight]
    ) async -> [RecommendationItem] {
        let scorer = scorerFactory()

        let localByDestination = Dictionary(uniqueKeysWithValues: localInsights.map { ($0.destinationId, $0) })
        let travelerFeedbackEntries = travelerFeedback.filter { $0.sourceType != .local }
        let localFeedbackEntries = travelerFeedback.filter { $0.sourceType == .local }
        let feedbackByTrip = Dictionary(grouping: travelerFeedbackEntries, by: \.tripId)
        let feedbackCrowdingSensitivity = averageCrowdingSensitivity(trips: trips, feedbackByTrip: feedbackByTrip)
        let homeCoordinate = TravelDistanceCalculator.homeCoordinate(from: userProfile)
        let destinationsByID = Dictionary(uniqueKeysWithValues: destinations.map { ($0.id, $0) })
        let tripDestinationLookup = Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0.destinationId) })
        var localFeedbackByDestination: [UUID: [TravelerFeedback]] = [:]
        for entry in localFeedbackEntries {
            guard let destinationId = entry.destinationId ?? tripDestinationLookup[entry.tripId] else { continue }
            localFeedbackByDestination[destinationId, default: []].append(entry)
        }
        let behavior = buildBehaviorSignals(
            userProfile: userProfile,
            trips: trips,
            feedbackByTrip: feedbackByTrip,
            destinationsByID: destinationsByID,
            homeCoordinate: homeCoordinate
        )

        let dominantStyle = dominantStyle(profile: userProfile, behavior: behavior)

        let items = destinations.map { destination -> RecommendationItem in
            let travelDistanceKm = TravelDistanceCalculator.distanceKm(
                from: homeCoordinate,
                to: (destination.latitude, destination.longitude)
            )
            let features = buildFeatures(
                destination: destination,
                userProfile: userProfile,
                localInsight: localByDestination[destination.id],
                localFeedback: localFeedbackByDestination[destination.id] ?? [],
                feedbackCrowdingSensitivity: feedbackCrowdingSensitivity,
                travelDistanceKm: travelDistanceKm
            )

            let mlScore = scorer?.score(features) ?? fallbackScore(from: features)
            let behaviorScore = behaviorScore(
                destination: destination,
                features: features,
                behavior: behavior,
                travelDistanceKm: travelDistanceKm
            )
            let resolvedScore = clamp((mlScore * 0.72) + (behaviorScore * 0.28), min: 0, max: 1)

            let breakdown = RecommendationBreakdown(
                matchScore: Double(Int((features.preferenceScore * 100).rounded())),
                environmentalPenalty: features.environmentalPenalty,
                localApprovalFactor: features.localApprovalFactor,
                finalScore: Double(Int((resolvedScore * 100).rounded()))
            )

            let why = explainabilityService.why(
                destination: destination,
                breakdown: breakdown,
                userProfile: userProfile,
                dominantStyle: dominantStyle
            )

            let co2 = co2Estimator.estimate(
                distanceKm: travelDistanceKm,
                transportType: .plane,
                people: userProfile.peopleDefault
            )

            return RecommendationItem(
                destination: destination,
                matchScore: Int((features.preferenceScore * 100).rounded()),
                ecoScore: Int(destination.ecoScore.rounded()),
                estimatedCO2: co2,
                whyRecommended: why,
                breakdown: breakdown
            )
        }

        return items
            .sorted { lhs, rhs in lhs.breakdown.finalScore > rhs.breakdown.finalScore }
            .prefix(48)
            .map { $0 }
    }

    private func buildFeatures(
        destination: Destination,
        userProfile: UserProfile,
        localInsight: LocalInsight?,
        localFeedback: [TravelerFeedback],
        feedbackCrowdingSensitivity: Double,
        travelDistanceKm: Double
    ) -> CoreMLRecommendationFeatures {
        let budgetCenter = clamp(((userProfile.budgetMin + userProfile.budgetMax) / 2) / 5_000, min: 0, max: 1)

        let destinationCost = clamp(destination.costIndex, min: 0, max: 1)
        let budgetFit = 1 - abs(destinationCost - budgetCenter) / max(budgetCenter, 0.05)
        let budgetComponent = clamp(budgetFit, min: 0, max: 1)

        let seasonMatchCount = Set(destination.typicalSeason).intersection(Set(userProfile.preferredSeasons)).count
        let seasonMatch = Double(seasonMatchCount) / Double(max(1, userProfile.preferredSeasons.count))

        let styleMatch = styleMatch(for: destination.styles, profileWeights: userProfile.travelStyleWeights)

        let ecoScore = clamp(destination.ecoScore / 100, min: 0, max: 1)
        let climateMatch = userProfile.preferredSeasons.contains("Summer") && destination.climate == "Warm" ? 1.0 : 0.7

        let co2 = co2Estimator.estimate(
            distanceKm: travelDistanceKm,
            transportType: .plane,
            people: userProfile.peopleDefault
        )
        let normalizedCO2 = clamp(co2 / 3_500, min: 0, max: 1)

        let crowding = DestinationMetadataInferer.normalizeCrowding(destination.crowdingIndex)
        let crowdingEffect = crowding * ((feedbackCrowdingSensitivity + userProfile.ecoSensitivity) / 2)
        let localSustainability = clamp((localInsight?.sustainabilityScore ?? destination.ecoScore) / 100, min: 0, max: 1)
        let localCommunitySentiment: Double = {
            guard !localFeedback.isEmpty else { return 0.55 }
            let count = Double(localFeedback.count)
            let averageRating = localFeedback.map(\.rating).reduce(0, +)
            let normalizedRating = Double(averageRating) / (count * 5.0)
            let averageSustainability = localFeedback.map(\.sustainabilityPerception).reduce(0, +) / count
            let averageCrowding = localFeedback.map(\.crowding).reduce(0, +) / count
            return clamp(
                (normalizedRating * 0.70) +
                (averageSustainability * 0.20) +
                ((1 - averageCrowding) * 0.10),
                min: 0,
                max: 1
            )
        }()

        let preferenceScore = clamp(
            (budgetComponent * 0.26) +
            (seasonMatch * 0.16) +
            (styleMatch * 0.38) +
            (ecoScore * 0.1) +
            (climateMatch * 0.1),
            min: 0,
            max: 1
        )

        let environmentalPenalty = clamp((normalizedCO2 * 0.6) + (crowdingEffect * 0.4), min: 0, max: 0.9)
        let localApprovalFactor = clamp(
            0.72 + (localSustainability * 0.28) + (localCommunitySentiment * 0.35),
            min: 0.72,
            max: 1.35
        )

        return CoreMLRecommendationFeatures(
            budgetCenter: budgetCenter,
            destinationCost: destinationCost,
            seasonMatch: seasonMatch,
            styleMatch: styleMatch,
            ecoScore: ecoScore,
            climateMatch: climateMatch,
            normalizedCO2: normalizedCO2,
            crowdingEffect: clamp(crowdingEffect, min: 0, max: 1),
            localSustainability: localSustainability,
            preferenceScore: preferenceScore,
            environmentalPenalty: environmentalPenalty,
            localApprovalFactor: localApprovalFactor
        )
    }

    private func buildBehaviorSignals(
        userProfile: UserProfile,
        trips: [Trip],
        feedbackByTrip: [UUID: [TravelerFeedback]],
        destinationsByID: [UUID: Destination],
        homeCoordinate: (latitude: Double, longitude: Double)
    ) -> RecommendationBehaviorSignals {
        var styleScores: [String: Double] = [:]
        var countryScores: [String: Double] = [:]
        var climateScores: [String: Double] = [:]
        var visitedCountryKeys = Set<String>()
        var weightedDistanceSum = 0.0
        var weightTotal = 0.0

        for trip in trips {
            guard let destination = destinationsByID[trip.destinationId] else { continue }

            let feedback = feedbackByTrip[trip.id] ?? []
            let quality: Double
            if feedback.isEmpty {
                quality = 0.50
            } else {
                let avgRating = Double(feedback.map(\.rating).reduce(0, +)) / (Double(feedback.count) * 5.0)
                let avgValue = feedback.map(\.value).reduce(0, +) / Double(feedback.count)
                let avgSustainability = feedback.map(\.sustainabilityPerception).reduce(0, +) / Double(feedback.count)
                let avgCrowding = feedback.map(\.crowding).reduce(0, +) / Double(feedback.count)
                quality = clamp(
                    (avgRating * 0.50) +
                    (avgValue * 0.25) +
                    (avgSustainability * 0.15) +
                    ((1 - avgCrowding) * 0.10),
                    min: 0,
                    max: 1
                )
            }

            let weight = 0.35 + (quality * 1.15)
            let countryKey = PlaceCanonicalizer.canonicalCountryKey(destination.country)
            countryScores[countryKey, default: 0] += weight
            climateScores[destination.climate, default: 0] += weight
            visitedCountryKeys.insert(countryKey)

            for style in destination.styles {
                let styleKey = PlaceCanonicalizer.canonicalStyle(style)
                styleScores[styleKey, default: 0] += weight
            }

            let distance = TravelDistanceCalculator.distanceKm(
                from: homeCoordinate,
                to: (destination.latitude, destination.longitude)
            )
            weightedDistanceSum += distance * weight
            weightTotal += weight
        }

        let defaultPreferredDistance = clamp((userProfile.budgetMax - userProfile.budgetMin) * 2.1, min: 700, max: 9_500)
        let preferredDistance = weightTotal > 0
            ? clamp(weightedDistanceSum / weightTotal, min: 120, max: 18_000)
            : defaultPreferredDistance

        let behaviorStyleAffinity = normalized(scores: styleScores)
        let effectiveStyleAffinity = blendedStyleAffinity(
            profileWeights: userProfile.travelStyleWeights,
            behaviorAffinity: behaviorStyleAffinity,
            tripCount: trips.count
        )

        return RecommendationBehaviorSignals(
            styleAffinity: effectiveStyleAffinity,
            countryAffinity: normalized(scores: countryScores),
            climateAffinity: normalized(scores: climateScores),
            preferredDistanceKm: preferredDistance,
            visitedCountryKeys: visitedCountryKeys
        )
    }

    private func behaviorScore(
        destination: Destination,
        features: CoreMLRecommendationFeatures,
        behavior: RecommendationBehaviorSignals,
        travelDistanceKm: Double
    ) -> Double {
        let countryKey = PlaceCanonicalizer.canonicalCountryKey(destination.country)
        let countryAffinity = behavior.countryAffinity[countryKey] ?? 0
        let climateAffinity = behavior.climateAffinity[destination.climate] ?? 0

        let styleAffinityValues = destination.styles.map { behavior.styleAffinity[PlaceCanonicalizer.canonicalStyle($0)] ?? 0 }
        let styleAffinity = styleAffinityValues.isEmpty ? 0 : styleAffinityValues.reduce(0, +) / Double(styleAffinityValues.count)

        let distanceGap = abs(travelDistanceKm - behavior.preferredDistanceKm)
        let distanceAffinity = clamp(1 - (distanceGap / max(behavior.preferredDistanceKm, 1_200)), min: 0, max: 1)

        let noveltyBoost = behavior.visitedCountryKeys.contains(countryKey) ? 0.0 : 0.12
        let environmentalComponent = 1 - features.environmentalPenalty

        return clamp(
            (features.preferenceScore * 0.45) +
            (styleAffinity * 0.20) +
            (countryAffinity * 0.10) +
            (climateAffinity * 0.08) +
            (distanceAffinity * 0.12) +
            (environmentalComponent * 0.05) +
            noveltyBoost,
            min: 0,
            max: 1
        )
    }

    private func dominantStyle(profile: UserProfile, behavior: RecommendationBehaviorSignals) -> String {
        if let configuredDominant = profileDominantStyle(from: profile.travelStyleWeights) {
            return configuredDominant
        }
        if let firstBehavior = behavior.styleAffinity.max(by: { $0.value < $1.value })?.key {
            return firstBehavior
        }
        return "Culture"
    }

    private func styleMatch(
        for destinationStyles: [String],
        profileWeights: [String: Double]
    ) -> Double {
        let profile = canonicalNormalizedStyleWeights(from: profileWeights)
        guard !profile.isEmpty else { return 0.25 }

        let canonicalStyles = Array(NSOrderedSet(array: destinationStyles.map(PlaceCanonicalizer.canonicalStyle)).compactMap { $0 as? String })
        let weightedHits = canonicalStyles.enumerated().compactMap { index, style -> (value: Double, rankWeight: Double)? in
            guard let value = profile[style] else { return nil }
            let rankWeight = max(0.25, 1 - (Double(index) * 0.18))
            return (value, rankWeight)
        }

        guard !weightedHits.isEmpty else { return 0.10 }

        let weightedSum = weightedHits.reduce(0.0) { partial, entry in
            partial + (entry.value * entry.rankWeight)
        }
        let rankWeightSum = weightedHits.reduce(0.0) { partial, entry in
            partial + entry.rankWeight
        }
        let rankedAverage = weightedSum / max(rankWeightSum, 0.001)
        let strongest = weightedHits.map { $0.value }.max() ?? rankedAverage

        let preferenceBoost: Double
        if let dominant = profileDominantStyle(from: profileWeights) {
            preferenceBoost = canonicalStyles.contains(dominant) ? 0.12 : -0.08
        } else {
            preferenceBoost = 0
        }

        return clamp((rankedAverage * 0.62) + (strongest * 0.38) + preferenceBoost, min: 0, max: 1)
    }

    private func canonicalNormalizedStyleWeights(from rawWeights: [String: Double]) -> [String: Double] {
        var canonicalized: [String: Double] = [:]
        for (key, value) in rawWeights where value > 0 {
            let canonical = PlaceCanonicalizer.canonicalStyle(key)
            canonicalized[canonical, default: 0] += value
        }

        let sum = canonicalized.values.reduce(0, +)
        guard sum > 0 else { return [:] }
        return Dictionary(uniqueKeysWithValues: canonicalized.map { ($0.key, $0.value / sum) })
    }

    private func profileDominantStyle(from rawWeights: [String: Double]) -> String? {
        let profile = canonicalNormalizedStyleWeights(from: rawWeights)
        let ranked = profile.sorted { $0.value > $1.value }
        guard let first = ranked.first else { return nil }
        let secondValue = ranked.dropFirst().first?.value ?? 0
        guard first.value - secondValue >= 0.08 else { return nil }
        return first.key
    }

    private func blendedStyleAffinity(
        profileWeights: [String: Double],
        behaviorAffinity: [String: Double],
        tripCount: Int
    ) -> [String: Double] {
        let profileAffinity = canonicalNormalizedStyleWeights(from: profileWeights)
        if profileAffinity.isEmpty { return behaviorAffinity }
        if behaviorAffinity.isEmpty { return profileAffinity }

        let behaviorWeight = clamp(Double(tripCount) / 14.0, min: 0.20, max: 0.45)
        let profileWeight = 1 - behaviorWeight
        let allKeys = Set(profileAffinity.keys).union(behaviorAffinity.keys)
        var merged: [String: Double] = [:]
        for key in allKeys {
            let profileValue = profileAffinity[key] ?? 0
            let behaviorValue = behaviorAffinity[key] ?? 0
            merged[key] = (profileValue * profileWeight) + (behaviorValue * behaviorWeight)
        }
        return normalized(scores: merged)
    }

    private func averageCrowdingSensitivity(
        trips: [Trip],
        feedbackByTrip: [UUID: [TravelerFeedback]]
    ) -> Double {
        let values = trips.flatMap { feedbackByTrip[$0.id] ?? [] }.map(\.crowding)
        guard !values.isEmpty else { return 0.5 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func normalized(scores: [String: Double]) -> [String: Double] {
        guard let maxValue = scores.values.max(), maxValue > 0 else { return [:] }
        return Dictionary(uniqueKeysWithValues: scores.map { ($0.key, $0.value / maxValue) })
    }

    private func fallbackScore(from features: CoreMLRecommendationFeatures) -> Double {
        clamp(features.preferenceScore * (1 - features.environmentalPenalty) * features.localApprovalFactor, min: 0, max: 1)
    }

    private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }
}

private struct BundleCoreMLDestinationScorer: CoreMLDestinationScoring {
    private let model: MLModel

    init?() {
        guard let model = Self.loadModel() else { return nil }
        self.model = model
    }

    func score(_ features: CoreMLRecommendationFeatures) -> Double? {
        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "budget_center": MLFeatureValue(double: features.budgetCenter),
                "destination_cost": MLFeatureValue(double: features.destinationCost),
                "season_match": MLFeatureValue(double: features.seasonMatch),
                "style_match": MLFeatureValue(double: features.styleMatch),
                "eco_score": MLFeatureValue(double: features.ecoScore),
                "climate_match": MLFeatureValue(double: features.climateMatch),
                "normalized_co2": MLFeatureValue(double: features.normalizedCO2),
                "crowding_effect": MLFeatureValue(double: features.crowdingEffect),
                "local_sustainability": MLFeatureValue(double: features.localSustainability)
            ])

            let output = try model.prediction(from: input)
            if let value = output.featureValue(for: "predictedScore")?.doubleValue {
                return value
            }

            return output.featureNames
                .compactMap { output.featureValue(for: $0)?.doubleValue }
                .first
        } catch {
            return nil
        }
    }

    private static func loadModel(bundle: Bundle = .main) -> MLModel? {
        if let compiledURL = bundle.url(forResource: "WaypointRecommender", withExtension: "mlmodelc") {
            return try? MLModel(contentsOf: compiledURL)
        }

        guard let sourceURL = bundle.url(forResource: "WaypointRecommender", withExtension: "mlmodel") else {
            return nil
        }

        guard let compiledURL = try? MLModel.compileModel(at: sourceURL) else {
            return nil
        }

        return try? MLModel(contentsOf: compiledURL)
    }
}
