import Foundation

enum RecommendationCandidateCatalog {
    static func recommendationPool(
        existingDestinations: [Destination],
        homeCoordinate: (latitude: Double, longitude: Double)
    ) -> [Destination] {
        var byKey: [String: Destination] = [:]

        for destination in existingDestinations {
            destination.distanceKm = TravelDistanceCalculator.distanceKm(
                from: homeCoordinate,
                to: (destination.latitude, destination.longitude)
            )
            byKey[key(for: destination.name, country: destination.country)] = destination
        }

        var perCountryCounts: [String: Int] = [:]

        for city in cityCandidates {
            let country = countryName(for: city.countryCode)
            let cityKey = key(for: city.name, country: country)

            guard byKey[cityKey] == nil else { continue }
            guard perCountryCounts[country, default: 0] < 5 else { continue }

            let distanceKm = TravelDistanceCalculator.distanceKm(
                from: homeCoordinate,
                to: (city.latitude, city.longitude)
            )

            let inferred = DestinationMetadataInferer.infer(
                name: city.name,
                country: country,
                latitude: city.latitude,
                longitude: city.longitude,
                population: city.population,
                featureCode: city.featureCode,
                distanceKm: distanceKm
            )

            byKey[cityKey] = Destination(
                name: city.name,
                country: country,
                latitude: city.latitude,
                longitude: city.longitude,
                styles: inferred.styles,
                climate: inferred.climate,
                costIndex: inferred.costIndex,
                ecoScore: inferred.ecoScore,
                crowdingIndex: inferred.crowdingIndex,
                typicalSeason: inferred.typicalSeason,
                distanceKm: distanceKm
            )

            perCountryCounts[country, default: 0] += 1
        }

        return Array(byKey.values)
    }

    private struct CandidateCity {
        let name: String
        let countryCode: String
        let latitude: Double
        let longitude: Double
        let population: Int
        let featureCode: String
    }

    private static let cityCandidates: [CandidateCity] = loadCityCandidates()

    private static let countryNameByCode: [String: String] = {
        let englishLocale = Locale(identifier: "en_US_POSIX")
        var result: [String: String] = [:]

        for code in Locale.Region.isoRegions.map(\.identifier) {
            let uppercasedCode = code.uppercased()
            if let name = Locale.current.localizedString(forRegionCode: uppercasedCode)
                ?? englishLocale.localizedString(forRegionCode: uppercasedCode) {
                result[uppercasedCode] = name
            }
        }

        return result
    }()

    private static func loadCityCandidates() -> [CandidateCity] {
        var uniqueByKey: [String: CandidateCity] = [:]

        for entry in CityDataset.populatedPlaces {
            let featureCode = entry.featureCode
            guard isAcceptedFeatureCode(featureCode) else { continue }

            let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !name.contains("Arrondissement") else { continue }

            let countryCode = entry.countryCode
            guard countryCode.count == 2 else { continue }

            let population = entry.population
            guard population >= minimumPopulation(for: featureCode) else { continue }

            let uniqueKey = "\(PlaceCanonicalizer.normalizeText(name))|\(countryCode)"
            if let existing = uniqueByKey[uniqueKey] {
                if existing.population > population {
                    continue
                }
                if existing.population == population, featurePriority(existing.featureCode) <= featurePriority(featureCode) {
                    continue
                }
            }

            uniqueByKey[uniqueKey] = CandidateCity(
                name: name,
                countryCode: countryCode,
                latitude: entry.latitude,
                longitude: entry.longitude,
                population: population,
                featureCode: featureCode
            )
        }

        return uniqueByKey.values
            .sorted { lhs, rhs in
                if lhs.population == rhs.population {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.population > rhs.population
            }
            .prefix(1_800)
            .map { $0 }
    }

    private static func isAcceptedFeatureCode(_ featureCode: String) -> Bool {
        switch featureCode {
        case "PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4", "PPL":
            return true
        default:
            return false
        }
    }

    private static func minimumPopulation(for featureCode: String) -> Int {
        switch featureCode {
        case "PPLC":
            return 100_000
        case "PPLA", "PPLA2", "PPLA3", "PPLA4":
            return 120_000
        default:
            return 220_000
        }
    }

    private static func featurePriority(_ featureCode: String) -> Int {
        switch featureCode {
        case "PPLC": return 0
        case "PPLA": return 1
        case "PPLA2": return 2
        case "PPLA3": return 3
        case "PPLA4": return 4
        default: return 5
        }
    }

    private static func countryName(for countryCode: String) -> String {
        countryNameByCode[countryCode] ?? countryCode
    }

    private static func key(for city: String, country: String) -> String {
        PlaceCanonicalizer.canonicalCityKey(name: city, country: country)
    }
}
