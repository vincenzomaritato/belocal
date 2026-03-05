import Foundation
import Observation

@MainActor
@Observable
final class CityExplorerViewModel {
    var searchText = ""
    var selectedCity: ExplorerCity?
    var wikiInfo: CityWikiInfo?
    var attractions: [CityPlace] = []
    var restaurants: [CityPlace] = []
    var essentials: [CityPlace] = []
    var feedbackEntries: [TravelerFeedback] = []
    var matchedDestination: Destination?
    var matchedLocalInsight: LocalInsight?
    var personalizedBrief: String?

    var isLoadingInfo = false
    var isLoadingPlaces = false
    var isResolvingLocation = false
    var isGeneratingBrief = false

    var statusMessage: String?

    func resetStatus() {
        statusMessage = nil
    }

    func refreshLocalMatches(homeViewModel: HomeViewModel) {
        guard let selectedCity else { return }
        feedbackEntries = feedbackForCity(selectedCity, homeViewModel: homeViewModel)
        matchedDestination = destinationMatchForCity(selectedCity, homeViewModel: homeViewModel)
        matchedLocalInsight = matchedDestination.flatMap { destination in
            homeViewModel.localInsights.first(where: { $0.destinationId == destination.id })
        }
    }

    func applySelection(
        city: ExplorerCity,
        homeViewModel: HomeViewModel,
        service: CityExplorerService
    ) async {
        selectedCity = city
        statusMessage = nil
        feedbackEntries = feedbackForCity(city, homeViewModel: homeViewModel)
        matchedDestination = destinationMatchForCity(city, homeViewModel: homeViewModel)
        matchedLocalInsight = matchedDestination.flatMap { destination in
            homeViewModel.localInsights.first(where: { $0.destinationId == destination.id })
        }
        personalizedBrief = nil

        isLoadingInfo = true
        isLoadingPlaces = true
        isGeneratingBrief = true
        wikiInfo = nil
        attractions = []
        restaurants = []
        essentials = []

        async let fetchedInfo = service.fetchWikipediaInfo(for: city)
        async let fetchedAttractions = service.fetchPlaces(for: city, category: .attractions)
        async let fetchedRestaurants = service.fetchPlaces(for: city, category: .restaurants)
        async let fetchedEssentials = service.fetchPlaces(for: city, category: .essentials)

        let (info, activityItems, restaurantItems, essentialItems) = await (
            fetchedInfo,
            fetchedAttractions,
            fetchedRestaurants,
            fetchedEssentials
        )
        wikiInfo = info

        let profiledAttractions = personalizePlaces(
            activityItems,
            category: .attractions,
            userProfile: homeViewModel.userProfile
        )
        let profiledRestaurants = personalizePlaces(
            restaurantItems,
            category: .restaurants,
            userProfile: homeViewModel.userProfile
        )
        let profiledEssentials = personalizePlaces(
            essentialItems,
            category: .essentials,
            userProfile: homeViewModel.userProfile
        )

        attractions = profiledAttractions
        restaurants = profiledRestaurants
        essentials = profiledEssentials

        let briefService = FoundationModelsExplorerBriefService()
        personalizedBrief = await briefService.makeBrief(
            city: city,
            wikiInfo: info,
            attractions: profiledAttractions,
            restaurants: profiledRestaurants,
            essentials: profiledEssentials,
            userProfile: homeViewModel.userProfile,
            feedback: feedbackEntries,
            destination: matchedDestination,
            localInsight: matchedLocalInsight
        )

        isLoadingInfo = false
        isLoadingPlaces = false
        isGeneratingBrief = false

        if info == nil && activityItems.isEmpty && restaurantItems.isEmpty && essentialItems.isEmpty {
            statusMessage = "No online details found for this city yet. Try another city."
        }
    }

    private func personalizePlaces(
        _ places: [CityPlace],
        category: CityPlaceCategory,
        userProfile: UserProfile?
    ) -> [CityPlace] {
        guard !places.isEmpty else { return places }
        let feedbackStats = feedbackStats(feedbackEntries)

        let ranked = places.map { place -> CityPlace in
            let personalization = personalizationFor(
                place: place,
                category: category,
                userProfile: userProfile,
                feedbackStats: feedbackStats
            )

            return CityPlace(
                id: place.id,
                name: place.name,
                subtitle: place.subtitle,
                distanceLabel: place.distanceLabel,
                deeplink: place.deeplink,
                provider: place.provider,
                category: place.category,
                rating: place.rating,
                reviewCount: place.reviewCount,
                priceLevel: place.priceLevel,
                openNow: place.openNow,
                placeType: place.placeType,
                personalizationScore: personalization.score,
                personalizationReason: personalization.reason
            )
        }

        return ranked.sorted { lhs, rhs in
            (lhs.personalizationScore ?? 0) > (rhs.personalizationScore ?? 0)
        }
    }

    private func personalizationFor(
        place: CityPlace,
        category: CityPlaceCategory,
        userProfile: UserProfile?,
        feedbackStats: FeedbackStats
    ) -> (score: Double, reason: String) {
        var score = 0.0
        var reasonParts: [String] = []

        if let rating = place.rating {
            let ratingContribution = min(max(rating / 5, 0), 1) * 45
            score += ratingContribution
            reasonParts.append("Rating \(String(format: "%.1f", rating))/5")
        } else {
            score += 14
        }

        if let reviews = place.reviewCount {
            let confidence = min(log10(Double(max(reviews, 1))) / 4.0, 1.0) * 20
            score += confidence
            reasonParts.append("\(reviews) reviews")
        } else {
            score += 8
        }

        if let level = place.priceLevel, let profile = userProfile {
            let budgetFit = budgetFitScore(priceLevel: level, profile: profile)
            score += budgetFit
            if budgetFit > 10 {
                reasonParts.append("Fits your budget")
            }
        } else {
            score += 6
        }

        if place.openNow == true {
            score += 8
            reasonParts.append("Open now")
        }

        score += styleWeightBoost(category: category, profile: userProfile)
        score += feedbackAlignmentBoost(feedbackStats: feedbackStats, category: category)

        let reason = reasonParts.prefix(2).joined(separator: " · ")
        return (score, reason.isEmpty ? "Good fit for your profile" : reason)
    }

    private func styleWeightBoost(category: CityPlaceCategory, profile: UserProfile?) -> Double {
        guard let profile else { return 0 }
        let weights = profile.travelStyleWeights

        switch category {
        case .restaurants:
            return (weights["Food"] ?? 0) * 22
        case .attractions:
            let culture = weights["Culture"] ?? 0
            let nature = weights["Nature"] ?? 0
            let adventure = weights["Adventure"] ?? 0
            return ((culture + nature + adventure) / 3) * 24
        case .essentials:
            let wellness = weights["Wellness"] ?? 0
            return wellness * 12
        }
    }

    private func budgetFitScore(priceLevel: Int, profile: UserProfile) -> Double {
        let normalizedBudget = min(max((profile.budgetMax - profile.budgetMin) / 2500.0, 0), 2.0)
        let targetLevel: Double
        if normalizedBudget < 0.6 {
            targetLevel = 1
        } else if normalizedBudget < 1.2 {
            targetLevel = 2
        } else {
            targetLevel = 3
        }

        let distance = abs(Double(priceLevel) - targetLevel)
        return max(0, 18 - (distance * 7))
    }

    private func feedbackAlignmentBoost(feedbackStats: FeedbackStats, category: CityPlaceCategory) -> Double {
        guard feedbackStats.count > 0 else { return 0 }
        var boost = feedbackStats.value * 10
        boost += feedbackStats.sustainability * 6

        if category == .attractions {
            boost += max(0, (1.0 - feedbackStats.crowding) * 8)
        }
        return boost
    }

    private func feedbackStats(_ entries: [TravelerFeedback]) -> FeedbackStats {
        guard !entries.isEmpty else { return FeedbackStats.zero }

        let travelerEntries = entries.filter { $0.sourceType == .traveler }
        let localEntries = entries.filter { $0.sourceType == .local }
        let travelerWeight = travelerEntries.isEmpty ? 0.0 : 0.7
        let localWeight = localEntries.isEmpty ? 0.0 : 0.3
        let normalization = max(travelerWeight + localWeight, 1)

        func average(_ source: [TravelerFeedback], keyPath: KeyPath<TravelerFeedback, Double>) -> Double {
            guard !source.isEmpty else { return 0 }
            return source.map { $0[keyPath: keyPath] }.reduce(0, +) / Double(source.count)
        }

        let crowding = ((average(travelerEntries, keyPath: \.crowding) * travelerWeight) +
                        (average(localEntries, keyPath: \.crowding) * localWeight)) / normalization
        let value = ((average(travelerEntries, keyPath: \.value) * travelerWeight) +
                     (average(localEntries, keyPath: \.value) * localWeight)) / normalization
        let sustainability = ((average(travelerEntries, keyPath: \.sustainabilityPerception) * travelerWeight) +
                              (average(localEntries, keyPath: \.sustainabilityPerception) * localWeight)) / normalization

        return FeedbackStats(
            count: entries.count,
            crowding: min(max(crowding, 0), 1),
            value: min(max(value, 0), 1),
            sustainability: min(max(sustainability, 0), 1)
        )
    }

    private func destinationMatchForCity(_ city: ExplorerCity, homeViewModel: HomeViewModel) -> Destination? {
        homeViewModel.destinations.first(where: {
            normalize($0.name) == normalize(city.name) &&
            normalize($0.country) == normalize(city.country)
        })
    }

    private func feedbackForCity(_ city: ExplorerCity, homeViewModel: HomeViewModel) -> [TravelerFeedback] {
        let destination = destinationMatchForCity(city, homeViewModel: homeViewModel)
        let tripIDs = Set(
            homeViewModel.trips
                .filter { trip in
                    guard let destination else { return false }
                    return trip.destinationId == destination.id
                }
                .map(\.id)
        )

        let selectedCityName = normalize(city.name)
        let selectedCountryName = normalize(city.country)
        let selectedCountryCode = countryCode(forCountryName: city.country)

        return homeViewModel.travelerFeedback
            .filter { entry in
                if let destination,
                   let destinationId = entry.destinationId,
                   destinationId == destination.id {
                    return true
                }
                if tripIDs.contains(entry.tripId) {
                    return true
                }

                let entryCityName = normalize(entry.destinationName)
                let entryCountryName = normalize(entry.destinationCountry)
                let entryCountryCode = countryCode(forCountryName: entry.destinationCountry)

                let countryMatches = selectedCountryName == entryCountryName
                    || (selectedCountryCode != nil && selectedCountryCode == entryCountryCode)
                    || entryCountryName.isEmpty
                let cityMatches = cityNameMatches(entryCityName, selected: selectedCityName)

                return cityMatches && countryMatches
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func cityNameMatches(_ entryName: String, selected selectedName: String) -> Bool {
        guard !entryName.isEmpty, !selectedName.isEmpty else { return false }
        let normalizedEntry = canonicalCityAlias(for: entryName)
        let normalizedSelected = canonicalCityAlias(for: selectedName)

        if normalizedEntry == normalizedSelected {
            return true
        }
        if normalizedEntry.contains(normalizedSelected) || normalizedSelected.contains(normalizedEntry) {
            return true
        }
        if normalizedEntry.prefix(3) == normalizedSelected.prefix(3) {
            return true
        }
        return normalizedLevenshteinSimilarity(normalizedEntry, normalizedSelected) >= 0.48
    }

    private func normalizedLevenshteinSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        var previous = Array(0...right.count)
        for (i, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = i + 1

            for (j, rightCharacter) in right.enumerated() {
                let insertion = current[j] + 1
                let deletion = previous[j + 1] + 1
                let substitution = previous[j] + (leftCharacter == rightCharacter ? 0 : 1)
                current[j + 1] = min(insertion, deletion, substitution)
            }

            previous = current
        }

        let distance = previous[right.count]
        let maxLength = max(left.count, right.count)
        return 1 - (Double(distance) / Double(maxLength))
    }

    private func countryCode(forCountryName country: String) -> String? {
        Self.countryCodeByNormalizedName[normalize(country)]
    }

    private func canonicalCityAlias(for city: String) -> String {
        let normalized = normalize(city)
        return Self.cityAliasMap[normalized] ?? normalized
    }

    private static let countryCodeByNormalizedName: [String: String] = {
        let englishLocale = Locale(identifier: "e")
        var result: [String: String] = [:]

        for code in Locale.Region.isoRegions.map(\.identifier) {
            let uppercasedCode = code.uppercased()
            if let localized = Locale.current.localizedString(forRegionCode: uppercasedCode) {
                result[normalizeCountryLookup(localized)] = uppercasedCode
            }
            if let english = englishLocale.localizedString(forRegionCode: uppercasedCode) {
                result[normalizeCountryLookup(english)] = uppercasedCode
            }
        }

        return result
    }()

    private static let cityAliasMap: [String: String] = [
        "naples": "napoli",
        "napoli": "napoli",
        "rome": "roma",
        "roma": "roma",
        "florence": "firenze",
        "firenze": "firenze",
        "venice": "venezia",
        "venezia": "venezia",
        "milan": "milano",
        "milano": "milano",
        "turin": "torino",
        "torino": "torino"
    ]

    private static func normalizeCountryLookup(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FeedbackStats {
    let count: Int
    let crowding: Double
    let value: Double
    let sustainability: Double

    static let zero = FeedbackStats(count: 0, crowding: 0, value: 0, sustainability: 0)
}
