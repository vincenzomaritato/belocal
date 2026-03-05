import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class HomeViewModel {
    var userProfile: UserProfile?
    var destinations: [Destination] = []
    var trips: [Trip] = []
    var travelerFeedback: [TravelerFeedback] = []
    var localInsights: [LocalInsight] = []
    var recommendations: [RecommendationItem] = []

    var isLoading = false
    var isRefreshingRecommendations = false
    var isOfflineModeEnabled = false
    var errorMessage: String?
    private let recommendationPostProcessor = RecommendationPostProcessor()
    private var recommendationRefreshTask: Task<Void, Never>?
    private var recommendationRefreshGeneration: Int = 0

    var visitedCountryCodes: [String] {
        var uniqueCodes = Set<String>()

        for trip in trips {
            guard let destination = destination(for: trip),
                  let isoCode = isoCode(forCountry: destination.country) else { continue }
            uniqueCodes.insert(isoCode)
        }

        return Array(uniqueCodes).sorted()
    }

    func load(context: ModelContext, bootstrap: AppBootstrap, preferOffline: Bool = false) {
        isLoading = true
        isOfflineModeEnabled = preferOffline
        errorMessage = nil

        do {
            let profileDescriptor = FetchDescriptor<UserProfile>()
            userProfile = try context.fetch(profileDescriptor).first
            destinations = try context.fetch(FetchDescriptor<Destination>(sortBy: [SortDescriptor(\Destination.name)]))
            trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\Trip.startDate, order: .reverse)]))
            travelerFeedback = try context.fetch(FetchDescriptor<TravelerFeedback>(sortBy: [SortDescriptor(\TravelerFeedback.createdAt, order: .reverse)]))
            localInsights = try context.fetch(FetchDescriptor<LocalInsight>())
            if let profile = userProfile {
                updateDestinationDistances(using: profile, context: context)
                sanitizeDestinationMetadata(context: context)
            }
            isLoading = false
            refreshRecommendations(bootstrap: bootstrap, preferOffline: preferOffline)
        } catch {
            errorMessage = "Unable to load local data."
            isLoading = false
        }
    }

    func refreshExploreCollections(context: ModelContext) {
        errorMessage = nil

        do {
            if userProfile == nil {
                userProfile = try context.fetch(FetchDescriptor<UserProfile>()).first
            }
            destinations = try context.fetch(
                FetchDescriptor<Destination>(sortBy: [SortDescriptor(\Destination.name)])
            )
            trips = try context.fetch(
                FetchDescriptor<Trip>(sortBy: [SortDescriptor(\Trip.startDate, order: .reverse)])
            )
            travelerFeedback = try context.fetch(
                FetchDescriptor<TravelerFeedback>(sortBy: [SortDescriptor(\TravelerFeedback.createdAt, order: .reverse)])
            )
            localInsights = try context.fetch(FetchDescriptor<LocalInsight>())

            if let profile = userProfile {
                updateDestinationDistances(using: profile, context: context)
                sanitizeDestinationMetadata(context: context)
            }
        } catch {
            errorMessage = "Unable to load local data."
        }
    }

    func refreshRecommendations(bootstrap: AppBootstrap, preferOffline: Bool? = nil) {
        let shouldPreferOffline = preferOffline ?? isOfflineModeEnabled
        isOfflineModeEnabled = shouldPreferOffline

        guard let profile = userProfile else {
            recommendationRefreshTask?.cancel()
            isRefreshingRecommendations = false
            recommendations = []
            return
        }

        recommendationRefreshTask?.cancel()
        isRefreshingRecommendations = true
        recommendationRefreshGeneration += 1
        let refreshGeneration = recommendationRefreshGeneration

        let detachedProfile = profile.detachedCopy()
        let detachedDestinations = destinations.map { $0.detachedCopy() }
        let detachedTrips = trips.map { $0.detachedCopy() }
        let detachedTravelerFeedback = travelerFeedback.map { $0.detachedCopy() }
        let detachedLocalInsights = localInsights.map { $0.detachedCopy() }

        let engine: any RecommendationEngine = bootstrap.coreMLEngine

        recommendationRefreshTask = Task(priority: .userInitiated) { @MainActor [recommendationPostProcessor] in
            defer {
                if refreshGeneration == self.recommendationRefreshGeneration {
                    self.isRefreshingRecommendations = false
                }
            }

            let homeCoordinate = TravelDistanceCalculator.homeCoordinate(from: detachedProfile)
            let recommendationPool = await Self.computeOnBackground {
                RecommendationCandidateCatalog.recommendationPool(
                    existingDestinations: detachedDestinations,
                    homeCoordinate: homeCoordinate
                )
            }
            guard !Task.isCancelled else { return }

            let recs = await Self.computeOnBackground {
                await engine.recommendations(
                    userProfile: detachedProfile,
                    destinations: recommendationPool,
                    trips: detachedTrips,
                    travelerFeedback: detachedTravelerFeedback,
                    localInsights: detachedLocalInsights
                )
            }
            guard !Task.isCancelled else { return }

            let visitedDestinations = detachedTrips.compactMap { trip in
                recommendationPool.first(where: { $0.id == trip.destinationId })
            }

            let topRecommendations = await Self.computeOnBackground {
                recommendationPostProcessor.finalize(
                    recommendations: recs,
                    visitedDestinations: visitedDestinations,
                    userProfile: detachedProfile,
                    maxCount: 8
                )
            }
            guard !Task.isCancelled else { return }

            let enrichedRecommendations: [RecommendationItem]
            if shouldPreferOffline {
                enrichedRecommendations = topRecommendations
            } else {
                let narrated = await bootstrap.recommendationNarrativeService.enhance(
                    recommendations: topRecommendations,
                    userProfile: detachedProfile
                )

                let reviewCount = min(5, narrated.count)
                let reviewedHead = Array(narrated.prefix(reviewCount))
                let approvedHead = await bootstrap.recommendationQualityReviewService.filterApproved(
                    recommendations: reviewedHead,
                    userProfile: detachedProfile
                )

                let approvedIDs = Set(approvedHead.map(\.id))
                let orderedApprovedHead = reviewedHead.filter { approvedIDs.contains($0.id) }
                let tail = Array(narrated.dropFirst(reviewCount))
                let merged = orderedApprovedHead + tail
                enrichedRecommendations = merged.isEmpty ? narrated : merged
            }
            guard !Task.isCancelled else { return }

            guard refreshGeneration == self.recommendationRefreshGeneration else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                recommendations = enrichedRecommendations
            }
        }
    }

    func destination(for trip: Trip) -> Destination? {
        destinations.first(where: { $0.id == trip.destinationId })
    }

    func localInsight(for destination: Destination) -> LocalInsight? {
        localInsights.first(where: { $0.destinationId == destination.id })
    }

    func ecoAlternatives(for destination: Destination) -> [Destination] {
        let primaryStyle = destination.styles.first
        return destinations
            .filter { $0.id != destination.id }
            .filter { candidate in
                guard let primaryStyle else { return true }
                return candidate.styles.contains(primaryStyle)
            }
            .filter { $0.distanceKm < destination.distanceKm || $0.ecoScore >= destination.ecoScore }
            .sorted { lhs, rhs in
                if lhs.ecoScore == rhs.ecoScore {
                    return lhs.distanceKm < rhs.distanceKm
                }
                return lhs.ecoScore > rhs.ecoScore
            }
            .prefix(3)
            .map { $0 }
    }

    private func isoCode(forCountry countryName: String) -> String? {
        let normalizedCountryName = normalizeCountryName(countryName)

        if let directMatch = Self.countryLookup[normalizedCountryName] {
            return directMatch
        }

        if let fallback = Self.manualCountryCodeOverrides[normalizedCountryName] {
            return fallback
        }

        return nil
    }

    private func normalizeCountryName(_ value: String) -> String {
        PlaceCanonicalizer.normalizeText(value)
    }

    private static let countryLookup: [String: String] = {
        let englishLocale = Locale(identifier: "en_US_POSIX")
        var lookup: [String: String] = [:]

        for isoCode in Locale.Region.isoRegions.map(\.identifier) {
            if let englishName = englishLocale.localizedString(forRegionCode: isoCode) {
                let key = PlaceCanonicalizer.normalizeText(englishName)
                lookup[key] = isoCode
            }
        }

        for (name, isoCode) in manualCountryCodeOverrides {
            lookup[name] = isoCode
        }

        return lookup
    }()

    private static let manualCountryCodeOverrides: [String: String] = [
        "south korea": "KR",
        "north korea": "KP",
        "russia": "RU",
        "vietnam": "VN",
        "laos": "LA",
        "bolivia": "BO",
        "venezuela": "VE",
        "tanzania": "TZ",
        "syria": "SY",
        "moldova": "MD"
    ]

    private func updateDestinationDistances(using profile: UserProfile, context: ModelContext) {
        let homeCoordinate = TravelDistanceCalculator.homeCoordinate(from: profile)
        var changed = false

        for destination in destinations {
            let distance = TravelDistanceCalculator.distanceKm(
                from: homeCoordinate,
                to: (destination.latitude, destination.longitude)
            )
            if abs(destination.distanceKm - distance) > 0.5 {
                destination.distanceKm = distance
                changed = true
            }
        }

        if changed {
            try? context.save()
        }
    }

    private func sanitizeDestinationMetadata(context: ModelContext) {
        var changed = false

        for destination in destinations {
            let normalizedClimate = destination.climate.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
            if !normalizedClimate.isEmpty && normalizedClimate != destination.climate {
                destination.climate = normalizedClimate
                changed = true
            }

            let normalizedStyles = DestinationMetadataInferer.sanitizeStyles(destination.styles)
            if normalizedStyles != destination.styles {
                destination.styles = normalizedStyles
                changed = true
            }

            let normalizedCrowding = DestinationMetadataInferer.normalizeCrowding(destination.crowdingIndex)
            if abs(destination.crowdingIndex - normalizedCrowding) > 0.001 {
                destination.crowdingIndex = normalizedCrowding
                changed = true
            }

            let normalizedCost = DestinationMetadataInferer.normalizeCostIndex(destination.costIndex)
            if abs(destination.costIndex - normalizedCost) > 0.001 {
                destination.costIndex = normalizedCost
                changed = true
            }

            let sanitizedSeason = DestinationMetadataInferer.sanitizeSeason(
                destination.typicalSeason,
                climate: destination.climate,
                latitude: destination.latitude
            )
            if sanitizedSeason != destination.typicalSeason {
                destination.typicalSeason = sanitizedSeason
                changed = true
            }
        }

        if changed {
            try? context.save()
        }
    }

    private static func computeOnBackground<T>(
        _ work: @escaping () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    private static func computeOnBackground<T>(
        _ work: @escaping () async -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Task {
                    let value = await work()
                    continuation.resume(returning: value)
                }
            }
        }
    }
}

private extension UserProfile {
    func detachedCopy() -> UserProfile {
        UserProfile(
            id: id,
            name: name,
            homeCity: homeCity,
            homeCountry: homeCountry,
            budgetMin: budgetMin,
            budgetMax: budgetMax,
            preferredSeasons: preferredSeasons,
            travelStyleWeights: travelStyleWeights,
            ecoSensitivity: ecoSensitivity,
            peopleDefault: peopleDefault,
            homeLatitude: homeLatitude,
            homeLongitude: homeLongitude
        )
    }
}

private extension Destination {
    func detachedCopy() -> Destination {
        Destination(
            id: id,
            name: name,
            country: country,
            latitude: latitude,
            longitude: longitude,
            styles: styles,
            climate: climate,
            costIndex: costIndex,
            ecoScore: ecoScore,
            crowdingIndex: crowdingIndex,
            typicalSeason: typicalSeason,
            distanceKm: distanceKm
        )
    }
}

private extension Trip {
    func detachedCopy() -> Trip {
        Trip(
            id: id,
            userId: userId,
            destinationId: destinationId,
            startDate: startDate,
            endDate: endDate,
            transportType: transportType,
            people: people,
            budgetSpent: budgetSpent,
            co2Estimated: co2Estimated,
            ecoScoreSnapshot: ecoScoreSnapshot
        )
    }
}

private extension TravelerFeedback {
    func detachedCopy() -> TravelerFeedback {
        TravelerFeedback(
            id: id,
            tripId: tripId,
            destinationId: destinationId,
            destinationName: destinationName,
            destinationCountry: destinationCountry,
            rating: rating,
            tags: tags,
            text: text,
            crowding: crowding,
            value: value,
            sustainabilityPerception: sustainabilityPerception,
            sourceType: sourceType,
            authorHomeCity: authorHomeCity,
            authorHomeCountry: authorHomeCountry,
            sentiment: sentiment,
            createdAt: createdAt
        )
    }
}

private extension LocalInsight {
    func detachedCopy() -> LocalInsight {
        LocalInsight(
            id: id,
            destinationId: destinationId,
            sustainabilityScore: sustainabilityScore,
            authenticityScore: authenticityScore,
            overcrowdingScore: overcrowdingScore,
            summaryText: summaryText
        )
    }
}
