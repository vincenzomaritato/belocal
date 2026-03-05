import Foundation

struct RecommendationPostProcessor {
    func finalize(
        recommendations: [RecommendationItem],
        visitedDestinations: [Destination],
        userProfile: UserProfile,
        maxCount: Int = 8
    ) -> [RecommendationItem] {
        let home = TravelDistanceCalculator.homeCoordinate(from: userProfile)
        let filtered = removeVisitedAndNearDuplicates(
            recommendations: recommendations,
            visitedDestinations: visitedDestinations
        )

        let fallbackPool: [RecommendationItem]
        if filtered.isEmpty {
            fallbackPool = removeExactVisited(recommendations: recommendations, visitedDestinations: visitedDestinations)
        } else {
            fallbackPool = filtered
        }

        let deduped = removeIntraListDuplicates(fallbackPool)
        return diversifiedSelection(deduped, home: home, maxCount: maxCount)
    }

    private func removeVisitedAndNearDuplicates(
        recommendations: [RecommendationItem],
        visitedDestinations: [Destination]
    ) -> [RecommendationItem] {
        let visitedKeys = Set(visitedDestinations.map { PlaceCanonicalizer.canonicalCityKey(name: $0.name, country: $0.country) })
        let visitedCoordinates = visitedDestinations.map { ($0.latitude, $0.longitude, $0.name) }

        return recommendations.filter { item in
            let key = PlaceCanonicalizer.canonicalCityKey(name: item.destination.name, country: item.destination.country)
            if visitedKeys.contains(key) {
                return false
            }

            for visited in visitedCoordinates {
                let geoDistance = TravelDistanceCalculator.distanceKm(
                    from: (visited.0, visited.1),
                    to: (item.destination.latitude, item.destination.longitude)
                )
                if geoDistance <= 110 {
                    return false
                }

                let textSimilarity = PlaceCanonicalizer.jaccardSimilarity(visited.2, item.destination.name)
                if textSimilarity >= 0.86 {
                    return false
                }
            }

            return true
        }
    }

    private func removeExactVisited(
        recommendations: [RecommendationItem],
        visitedDestinations: [Destination]
    ) -> [RecommendationItem] {
        let visitedKeys = Set(visitedDestinations.map { PlaceCanonicalizer.canonicalCityKey(name: $0.name, country: $0.country) })
        return recommendations.filter { item in
            !visitedKeys.contains(PlaceCanonicalizer.canonicalCityKey(name: item.destination.name, country: item.destination.country))
        }
    }

    private func removeIntraListDuplicates(_ items: [RecommendationItem]) -> [RecommendationItem] {
        var selected: [RecommendationItem] = []

        for item in items {
            var hasDuplicate = false
            for existing in selected {
                let sameCountry = PlaceCanonicalizer.canonicalCountryKey(existing.destination.country)
                    == PlaceCanonicalizer.canonicalCountryKey(item.destination.country)
                let textSimilarity = PlaceCanonicalizer.jaccardSimilarity(existing.destination.name, item.destination.name)
                let geoDistance = TravelDistanceCalculator.distanceKm(
                    from: (existing.destination.latitude, existing.destination.longitude),
                    to: (item.destination.latitude, item.destination.longitude)
                )
                if (sameCountry && textSimilarity >= 0.80) || geoDistance < 55 {
                    hasDuplicate = true
                    break
                }
            }

            if !hasDuplicate {
                selected.append(item)
            }
        }

        return selected
    }

    private func diversifiedSelection(
        _ items: [RecommendationItem],
        home: (latitude: Double, longitude: Double),
        maxCount: Int
    ) -> [RecommendationItem] {
        var pool = items
        var picked: [RecommendationItem] = []
        var countries = Set<String>()
        var primaryStyles = Set<String>()
        var distanceBuckets = Set<Int>()
        var climates = Set<String>()

        while !pool.isEmpty && picked.count < maxCount {
            let scored = pool.enumerated().map { index, item -> (Int, Double) in
                let base = item.breakdown.finalScore / 100
                let countryKey = PlaceCanonicalizer.canonicalCountryKey(item.destination.country)
                let primaryStyle = PlaceCanonicalizer.canonicalStyle(item.destination.styles.first ?? "Culture")
                let distanceBucket = Int(TravelDistanceCalculator.distanceKm(from: home, to: (item.destination.latitude, item.destination.longitude)) / 2_000)
                let climate = item.destination.climate

                var diversity: Double = 0
                if !countries.contains(countryKey) { diversity += 0.24 }
                if !primaryStyles.contains(primaryStyle) { diversity += 0.22 }
                if !distanceBuckets.contains(distanceBucket) { diversity += 0.14 }
                if !climates.contains(climate) { diversity += 0.08 }

                for pickedItem in picked {
                    let distance = TravelDistanceCalculator.distanceKm(
                        from: (pickedItem.destination.latitude, pickedItem.destination.longitude),
                        to: (item.destination.latitude, item.destination.longitude)
                    )
                    if distance < 180 {
                        diversity -= 0.20
                    }
                }

                return (index, (base * 0.72) + (diversity * 0.28))
            }

            guard let winner = scored.max(by: { $0.1 < $1.1 }) else { break }
            let selected = pool.remove(at: winner.0)
            picked.append(selected)

            countries.insert(PlaceCanonicalizer.canonicalCountryKey(selected.destination.country))
            primaryStyles.insert(PlaceCanonicalizer.canonicalStyle(selected.destination.styles.first ?? "Culture"))
            let bucket = Int(TravelDistanceCalculator.distanceKm(from: home, to: (selected.destination.latitude, selected.destination.longitude)) / 2_000)
            distanceBuckets.insert(bucket)
            climates.insert(selected.destination.climate)
        }

        return picked
    }
}
