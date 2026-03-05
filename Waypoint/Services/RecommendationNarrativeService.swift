import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
protocol RecommendationNarrativeServing {
    func enhance(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem]
}

struct PassthroughRecommendationNarrativeService: RecommendationNarrativeServing {
    func enhance(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem] {
        recommendations
    }
}

struct FoundationModelsRecommendationNarrativeService: RecommendationNarrativeServing {
    func enhance(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem] {
        guard !recommendations.isEmpty else { return [] }

#if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt(for: recommendations, userProfile: userProfile))
            let responseText = responseContent(from: response)
            return NarrativeMerge.mergeNarratives(from: responseText, with: recommendations)
        } catch {
            return recommendations
        }
#else
        return recommendations
#endif
    }

    private func prompt(
        for recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) -> String {
        let bullets = recommendations.enumerated().map { index, item in
            let score = Int(item.breakdown.finalScore.rounded())
            return "\(index + 1). city: \(item.destination.name), country: \(item.destination.country), styles: \(item.destination.styles.joined(separator: ", ")), score: \(score), eco: \(item.ecoScore), costIndex: \(String(format: "%.2f", item.destination.costIndex))"
        }
        .joined(separator: "\n")

        return """
        You are generating custom recommendation snippets for a travel card UI.
        Traveler profile:
        - budget: \(Int(userProfile.budgetMin))-\(Int(userProfile.budgetMax)) EUR
        - preferred seasons: \(userProfile.preferredSeasons.joined(separator: ", "))
        - eco sensitivity: \(Int((userProfile.ecoSensitivity * 100).rounded()))/100
        - output language: \(preferredNarrativeLanguage)

        Destinations:
        \(bullets)

        Return ONLY valid JSON in this exact shape:
        {"items":[{"index":1,"text":"..."}]}

        Rules:
        - provide exactly \(recommendations.count) items
        - each text max 24 words
        - each text must start with the destination city name
        - do not start with "Recommended"
        - one complete sentence, practical and specific tone
        - mention at least one concrete reason (budget, season, distance, sustainability, or travel style)
        """
    }

    private func responseContent<T>(from response: T) -> String {
        let mirror = Mirror(reflecting: response)
        for child in mirror.children {
            guard child.label == "content" || child.label == "outputText" else { continue }
            if let text = child.value as? String {
                return text
            }
        }
        return String(describing: response)
    }

    private var preferredNarrativeLanguage: String {
        "English"
    }
}

struct OpenAIRecommendationNarrativeService: RecommendationNarrativeServing {
    let openAIChatService: any OpenAIChatServing

    func enhance(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem] {
        guard !recommendations.isEmpty else { return [] }

        do {
            let reply = try await openAIChatService.send(
                userMessage: prompt(for: recommendations, userProfile: userProfile),
                previousResponseID: nil
            )
            return NarrativeMerge.mergeNarratives(from: reply.text, with: recommendations)
        } catch {
            return recommendations
        }
    }

    private func prompt(
        for recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) -> String {
        let lines = recommendations.enumerated().map { index, item in
            "\(index + 1)|\(item.destination.name)|\(item.destination.country)|styles=\(item.destination.styles.joined(separator: ","))|score=\(Int(item.breakdown.finalScore.rounded()))"
        }
        .joined(separator: "\n")

        return """
        Rewrite travel recommendation card subtitles.
        Traveler profile:
        - budget range: \(Int(userProfile.budgetMin))-\(Int(userProfile.budgetMax)) EUR
        - preferred seasons: \(userProfile.preferredSeasons.joined(separator: ", "))
        - eco sensitivity: \(Int((userProfile.ecoSensitivity * 100).rounded()))/100
        - output language: \(preferredNarrativeLanguage)

        Destinations:
        \(lines)

        Return ONLY JSON:
        {"items":[{"index":1,"text":"..."}]}

        Constraints:
        - exactly \(recommendations.count) items
        - max 24 words per item
        - must begin with destination city name
        - do not use the word "Recommended"
        - one complete sentence, concise, practical, personalized
        - mention at least one concrete reason (budget, season, distance, sustainability, or travel style)
        """
    }

    private var preferredNarrativeLanguage: String {
        "English"
    }
}

struct HybridRecommendationNarrativeService: RecommendationNarrativeServing {
    let primary: any RecommendationNarrativeServing
    let secondary: any RecommendationNarrativeServing

    func enhance(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem] {
        let primaryOutput = await primary.enhance(recommendations: recommendations, userProfile: userProfile)
        if hasMeaningfulRewrite(original: recommendations, rewritten: primaryOutput) {
            return primaryOutput
        }
        return await secondary.enhance(recommendations: primaryOutput, userProfile: userProfile)
    }

    private func hasMeaningfulRewrite(
        original: [RecommendationItem],
        rewritten: [RecommendationItem]
    ) -> Bool {
        guard original.count == rewritten.count else { return true }
        return zip(original, rewritten).contains { lhs, rhs in
            lhs.whyRecommended.trimmingCharacters(in: .whitespacesAndNewlines)
                != rhs.whyRecommended.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

private enum NarrativeMerge {
    static func mergeNarratives(
        from modelOutput: String,
        with recommendations: [RecommendationItem]
    ) -> [RecommendationItem] {
        let rewrittenByIndex = parseNarratives(from: modelOutput, expectedCount: recommendations.count)

        return recommendations.enumerated().map { index, item in
            RecommendationItem(
                destination: item.destination,
                matchScore: item.matchScore,
                ecoScore: item.ecoScore,
                estimatedCO2: item.estimatedCO2,
                whyRecommended: rewrittenByIndex[index].flatMap { $0.isEmpty ? nil : $0 } ?? item.whyRecommended,
                breakdown: item.breakdown
            )
        }
    }

    private static func parseNarratives(from rawOutput: String, expectedCount: Int) -> [Int: String] {
        let jsonParsed = parseJSONNarratives(from: rawOutput, expectedCount: expectedCount)
        if !jsonParsed.isEmpty {
            return jsonParsed
        }
        return parseLineNarratives(from: rawOutput, expectedCount: expectedCount)
    }

    private static func parseJSONNarratives(from rawOutput: String, expectedCount: Int) -> [Int: String] {
        let candidates = [rawOutput, extractJSONObject(from: rawOutput)].compactMap { $0 }

        for candidate in candidates {
            if let parsed = decodeNarrativeItemsJSON(candidate, expectedCount: expectedCount), !parsed.isEmpty {
                return parsed
            }
        }

        return [:]
    }

    private static func decodeNarrativeItemsJSON(_ json: String, expectedCount: Int) -> [Int: String]? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(NarrativeEnvelope.self, from: data) {
            return mapNarrativeItems(envelope.items, expectedCount: expectedCount)
        }

        if let items = try? decoder.decode([NarrativeItem].self, from: data) {
            return mapNarrativeItems(items, expectedCount: expectedCount)
        }

        return nil
    }

    private static func mapNarrativeItems(_ items: [NarrativeItem], expectedCount: Int) -> [Int: String] {
        var byIndex: [Int: String] = [:]
        for item in items {
            guard item.index >= 1, item.index <= expectedCount else { continue }
            let cleaned = cleanedNarrative(item.text)
            guard !cleaned.isEmpty else { continue }
            byIndex[item.index - 1] = cleaned
        }
        return byIndex
    }

    private static func parseLineNarratives(from rawOutput: String, expectedCount: Int) -> [Int: String] {
        let lines = rawOutput
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var byIndex: [Int: String] = [:]
        let pattern = #"^\s*(\d+)\s*[\|\:\-\.\)]\s*(.+)$"#
        let regex = try? NSRegularExpression(pattern: pattern)

        for line in lines {
            if let pipeSplit = parsePipeLine(line, expectedCount: expectedCount) {
                byIndex[pipeSplit.0] = pipeSplit.1
                continue
            }

            guard let regex else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges == 3,
                  let indexRange = Range(match.range(at: 1), in: line),
                  let textRange = Range(match.range(at: 2), in: line),
                  let oneBased = Int(line[indexRange]),
                  oneBased >= 1,
                  oneBased <= expectedCount else { continue }

            let cleaned = cleanedNarrative(String(line[textRange]))
            guard !cleaned.isEmpty else { continue }
            byIndex[oneBased - 1] = cleaned
        }

        return byIndex
    }

    private static func parsePipeLine(_ line: String, expectedCount: Int) -> (Int, String)? {
        let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let oneBasedIndex = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              oneBasedIndex >= 1,
              oneBasedIndex <= expectedCount else { return nil }

        let cleaned = cleanedNarrative(parts[1])
        guard !cleaned.isEmpty else { return nil }
        return (oneBasedIndex - 1, cleaned)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}") else { return nil }
        guard first <= last else { return nil }
        return String(text[first...last])
    }

    private static func cleanedNarrative(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if cleaned.hasPrefix("Recommended because ") {
            cleaned = String(cleaned.dropFirst("Recommended because ".count))
        } else if cleaned.hasPrefix("Recommended ") {
            cleaned = String(cleaned.dropFirst("Recommended ".count))
        }
        return cleaned
    }
}

private struct NarrativeEnvelope: Decodable {
    let items: [NarrativeItem]
}

private struct NarrativeItem: Decodable {
    let index: Int
    let text: String
}
