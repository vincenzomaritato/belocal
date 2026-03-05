import Foundation

enum DestinationMetadataInferer {
    struct Metadata {
        let styles: [String]
        let climate: String
        let costIndex: Double
        let ecoScore: Double
        let crowdingIndex: Double
        let typicalSeason: [String]
    }

    static func infer(
        name: String,
        country: String,
        latitude: Double,
        longitude: Double,
        population: Int?,
        featureCode: String?,
        distanceKm: Double
    ) -> Metadata {
        let resolvedPopulation = max(population ?? 350_000, 20_000)
        let crowding = inferredCrowdingIndex(population: resolvedPopulation)
        let climate = inferredClimate(latitude: latitude)
        let typicalSeason = inferredTypicalSeason(climate: climate)
        let styles = inferredStyles(
            name: name,
            country: country,
            latitude: latitude,
            population: resolvedPopulation,
            featureCode: featureCode,
            crowdingIndex: crowding
        )
        let cost = inferredCostIndex(population: resolvedPopulation, distanceKm: distanceKm)
        let eco = inferredEcoScore(climate: climate, crowdingIndex: crowding, distanceKm: distanceKm)

        return Metadata(
            styles: styles,
            climate: climate,
            costIndex: cost,
            ecoScore: eco,
            crowdingIndex: crowding,
            typicalSeason: typicalSeason
        )
    }

    static func sanitizeStyles(_ styles: [String]) -> [String] {
        let canonical = styles.map(PlaceCanonicalizer.canonicalStyle)
        let deduped = Array(NSOrderedSet(array: canonical).compactMap { $0 as? String })
        return deduped.isEmpty ? ["Culture", "Food", "Nature"] : deduped
    }

    static func sanitizeSeason(_ seasons: [String], climate: String, latitude: Double) -> [String] {
        let canonical = Array(
            NSOrderedSet(
                array: seasons.map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().capitalized
                }
            ).compactMap { $0 as? String }
        )
        if canonical.isEmpty {
            return inferredTypicalSeason(climate: climate.isEmpty ? inferredClimate(latitude: latitude) : climate)
        }
        return canonical
    }

    static func normalizeCrowding(_ raw: Double) -> Double {
        if raw > 1.0 {
            return clamp(raw / 100.0, min: 0.0, max: 1.0)
        }
        return clamp(raw, min: 0.0, max: 1.0)
    }

    static func normalizeCostIndex(_ raw: Double) -> Double {
        if raw > 1.0 {
            return clamp(raw / 5.0, min: 0.25, max: 1.0)
        }
        return clamp(raw, min: 0.25, max: 1.0)
    }

    private static func inferredStyles(
        name: String,
        country: String,
        latitude: Double,
        population: Int,
        featureCode: String?,
        crowdingIndex: Double
    ) -> [String] {
        var styles: [String] = []

        func append(_ style: String) {
            let canonical = PlaceCanonicalizer.canonicalStyle(style)
            if !styles.contains(canonical) {
                styles.append(canonical)
            }
        }

        let normalizedFeature = PlaceCanonicalizer.normalizeText(featureCode ?? "")

        if normalizedFeature == "pplc" || normalizedFeature == "ppla" || population >= 2_000_000 {
            append("Culture")
            append("Food")
            append("Urban")
        } else {
            append("Culture")
        }

        if abs(latitude) < 32 {
            append("Beach")
        }

        if population <= 900_000 || abs(latitude) > 46 {
            append("Nature")
        }

        if crowdingIndex <= 0.35 {
            append("Slow Travel")
        } else if crowdingIndex >= 0.70 {
            append("Nightlife")
            append("Shopping")
        }

        let stableHash = stableStyleHash(name: name, country: country)
        let secondary = ["Design", "History", "Adventure", "Wellness"]
        append(secondary[stableHash % secondary.count])

        return styles
    }

    private static func inferredClimate(latitude: Double) -> String {
        let absLatitude = abs(latitude)
        if absLatitude < 24 {
            return "Warm"
        }
        if absLatitude < 46 {
            return "Temperate"
        }
        return "Cool"
    }

    private static func inferredTypicalSeason(climate: String) -> [String] {
        switch climate {
        case "Warm":
            return ["Spring", "Autumn", "Winter"]
        case "Cool":
            return ["Spring", "Summer"]
        default:
            return ["Spring", "Summer", "Autumn"]
        }
    }

    private static func inferredCostIndex(population: Int, distanceKm: Double) -> Double {
        let populationComponent = clamp(log10(Double(max(population, 1))) / 8.0, min: 0, max: 1) * 0.30
        let distanceComponent = clamp(distanceKm / 12_000.0, min: 0, max: 1) * 0.22
        return clamp(0.34 + populationComponent + distanceComponent, min: 0.28, max: 0.93)
    }

    private static func inferredEcoScore(climate: String, crowdingIndex: Double, distanceKm: Double) -> Double {
        let climateBoost: Double
        switch climate {
        case "Cool": climateBoost = 4
        case "Temperate": climateBoost = 2
        default: climateBoost = 0
        }
        let crowdingPenalty = crowdingIndex * 26
        let distancePenalty = clamp(distanceKm / 16_000.0, min: 0, max: 1) * 12
        return clamp(86 + climateBoost - crowdingPenalty - distancePenalty, min: 46, max: 95)
    }

    private static func inferredCrowdingIndex(population: Int) -> Double {
        let normalized = clamp((log10(Double(max(population, 1))) - 4.3) / 3.0, min: 0, max: 1)
        return clamp((normalized * 0.88) + 0.06, min: 0.08, max: 0.94)
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }

    private static func stableStyleHash(name: String, country: String) -> Int {
        let joined = PlaceCanonicalizer.normalizeText(name) + "|" + PlaceCanonicalizer.normalizeText(country)
        var value = 0
        for scalar in joined.unicodeScalars {
            value = (value &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return value
    }
}
