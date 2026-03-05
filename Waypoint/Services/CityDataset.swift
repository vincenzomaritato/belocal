import Foundation

struct CityDatasetEntry: Hashable, Sendable {
    let name: String
    let asciiName: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let population: Int
    let featureClass: String
    let featureCode: String
}

enum CityDataset {
    static var entries: [CityDatasetEntry] { storage.entries }
    static var populatedPlaces: [CityDatasetEntry] { storage.populatedPlaces }
    static var populatedPlacesByCountryCode: [String: [CityDatasetEntry]] { storage.populatedPlacesByCountryCode }

    static func prewarm() {
        _ = storage
    }

    private static let storage = CityDatasetStorage()
}

private struct CityDatasetStorage {
    let entries: [CityDatasetEntry]
    let populatedPlaces: [CityDatasetEntry]
    let populatedPlacesByCountryCode: [String: [CityDatasetEntry]]

    init(bundle: Bundle = .main) {
        let loadedEntries = Self.loadEntries(bundle: bundle)
        entries = loadedEntries

        let resolvedPopulatedPlaces = loadedEntries.filter {
            $0.featureClass == "P" && $0.featureCode.hasPrefix("PPL")
        }
        populatedPlaces = resolvedPopulatedPlaces

        let grouped = Dictionary(grouping: resolvedPopulatedPlaces) { $0.countryCode }
        populatedPlacesByCountryCode = grouped.mapValues { list in
            list.sorted { lhs, rhs in
                if lhs.population == rhs.population {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.population > rhs.population
            }
        }
    }

    private static func loadEntries(bundle: Bundle) -> [CityDatasetEntry] {
        guard let url = bundle.url(forResource: "cities", withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var dedupedByKey: [String: CityDatasetEntry] = [:]

        for line in content.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count > 14 else { continue }

            let featureClass = String(fields[6]).uppercased()
            let featureCode = String(fields[7]).uppercased()
            guard featureClass == "P" else { continue }

            let countryCode = String(fields[8]).uppercased()
            guard countryCode.count == 2 else { continue }

            let name = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let asciiName = String(fields[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let latitude = Double(fields[4]), let longitude = Double(fields[5]) else { continue }
            let population = Int(fields[14]) ?? 0

            let entry = CityDatasetEntry(
                name: name,
                asciiName: asciiName,
                countryCode: countryCode,
                latitude: latitude,
                longitude: longitude,
                population: population,
                featureClass: featureClass,
                featureCode: featureCode
            )

            let dedupeKey = "\(countryCode)|\(normalizedKey(name))|\(Int(latitude * 10_000))|\(Int(longitude * 10_000))"
            if let existing = dedupedByKey[dedupeKey], existing.population > entry.population {
                continue
            }
            dedupedByKey[dedupeKey] = entry
        }

        return dedupedByKey.values.sorted { lhs, rhs in
            if lhs.population == rhs.population {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.population > rhs.population
        }
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
