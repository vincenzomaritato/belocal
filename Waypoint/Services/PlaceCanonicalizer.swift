import Foundation

enum PlaceCanonicalizer {
    nonisolated static func normalizeText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "'", with: "")
            .lowercased()
    }

    nonisolated static func canonicalCityKey(name: String, country: String) -> String {
        "\(normalizeText(name))|\(normalizeText(country))"
    }

    nonisolated static func canonicalCountryKey(_ country: String) -> String {
        normalizeText(country)
    }

    nonisolated static func normalizedTokens(_ value: String) -> Set<String> {
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return Set(
            normalizeText(value)
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 1 }
        )
    }

    nonisolated static func jaccardSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let left = normalizedTokens(lhs)
        let right = normalizedTokens(rhs)
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        let intersection = left.intersection(right).count
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(intersection) / Double(union)
    }

    nonisolated static func canonicalStyle(_ style: String) -> String {
        switch normalizeText(style) {
        case "culture", "history", "heritage":
            return "Culture"
        case "food", "foodie", "cuisine":
            return "Food"
        case "nature", "outdoors":
            return "Nature"
        case "beach", "coast":
            return "Beach"
        case "explore", "exploration":
            return "Adventure"
        case "urban", "city":
            return "Urban"
        case "adventure":
            return "Adventure"
        case "wellness":
            return "Wellness"
        case "nightlife":
            return "Nightlife"
        case "design":
            return "Design"
        case "shopping":
            return "Shopping"
        case "slow travel", "slow":
            return "Slow Travel"
        default:
            return style
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .capitalized
        }
    }
}
