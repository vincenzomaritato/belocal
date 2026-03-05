import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
protocol RecommendationQualityReviewServing {
    func filterApproved(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem]
}

struct PassthroughRecommendationQualityReviewService: RecommendationQualityReviewServing {
    func filterApproved(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem] {
        recommendations
    }
}

struct FoundationModelsRecommendationQualityReviewService: RecommendationQualityReviewServing {
    func filterApproved(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem] {
        guard !recommendations.isEmpty else { return [] }

#if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt(for: recommendations, userProfile: userProfile))
            let responseText = responseContent(from: response)
            return RecommendationQualityMerge.mergeReviewed(
                from: responseText,
                recommendations: recommendations
            )
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
        let lines = recommendations.enumerated().map { index, item in
            let score = Int(item.breakdown.finalScore.rounded())
            return "\(index + 1). city=\(item.destination.name), country=\(item.destination.country), styles=\(item.destination.styles.joined(separator: ",")), score=\(score), eco=\(item.ecoScore), co2=\(Int(item.estimatedCO2)), why=\(item.whyRecommended)"
        }
        .joined(separator: "\n")

        return """
        Review travel recommendations and decide if each one is acceptable for this traveler.

        Traveler profile:
        - budget: \(Int(userProfile.budgetMin))-\(Int(userProfile.budgetMax)) EUR
        - preferred seasons: \(userProfile.preferredSeasons.joined(separator: ", "))
        - eco sensitivity: \(Int((userProfile.ecoSensitivity * 100).rounded()))/100

        Recommendations:
        \(lines)

        Return ONLY valid JSON:
        {"items":[{"index":1,"ok":true,"reason":"short reason"}]}

        Rules:
        - include exactly \(recommendations.count) items
        - index is 1-based
        - ok=true only if recommendation is coherent with profile constraints
        - reason max 12 words
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
}

struct OpenAIRecommendationQualityReviewService: RecommendationQualityReviewServing {
    let openAIChatService: any OpenAIChatServing

    func filterApproved(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem] {
        guard !recommendations.isEmpty else { return [] }

        do {
            let reply = try await openAIChatService.send(
                userMessage: prompt(for: recommendations, userProfile: userProfile),
                previousResponseID: nil
            )

            return RecommendationQualityMerge.mergeReviewed(
                from: reply.text,
                recommendations: recommendations
            )
        } catch {
            return recommendations
        }
    }

    private func prompt(
        for recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) -> String {
        let lines = recommendations.enumerated().map { index, item in
            let score = Int(item.breakdown.finalScore.rounded())
            return "\(index + 1)|\(item.destination.name)|\(item.destination.country)|styles=\(item.destination.styles.joined(separator: ","))|score=\(score)|eco=\(item.ecoScore)|co2=\(Int(item.estimatedCO2))|why=\(item.whyRecommended)"
        }
        .joined(separator: "\n")

        return """
        Validate each travel recommendation for profile fit.

        Traveler profile:
        - budget range: \(Int(userProfile.budgetMin))-\(Int(userProfile.budgetMax)) EUR
        - preferred seasons: \(userProfile.preferredSeasons.joined(separator: ", "))
        - eco sensitivity: \(Int((userProfile.ecoSensitivity * 100).rounded()))/100

        Recommendations:
        \(lines)

        Return ONLY JSON:
        {"items":[{"index":1,"ok":true,"reason":"short reason"}]}

        Constraints:
        - exactly \(recommendations.count) items
        - index is 1-based
        - reason max 12 words
        """
    }
}

struct HybridRecommendationQualityReviewService: RecommendationQualityReviewServing {
    let primary: any RecommendationQualityReviewServing
    let secondary: any RecommendationQualityReviewServing

    func filterApproved(
        recommendations: [RecommendationItem],
        userProfile: UserProfile
    ) async -> [RecommendationItem] {
        let primaryReviewed = await primary.filterApproved(
            recommendations: recommendations,
            userProfile: userProfile
        )

        if isMeaningfulFilter(input: recommendations, output: primaryReviewed) {
            return primaryReviewed
        }

        return await secondary.filterApproved(
            recommendations: recommendations,
            userProfile: userProfile
        )
    }

    private func isMeaningfulFilter(input: [RecommendationItem], output: [RecommendationItem]) -> Bool {
        guard !input.isEmpty else { return true }
        guard !output.isEmpty else { return false }
        return output.count <= input.count
    }
}

private enum RecommendationQualityMerge {
    static func mergeReviewed(
        from rawOutput: String,
        recommendations: [RecommendationItem]
    ) -> [RecommendationItem] {
        let decisions = parseDecisions(from: rawOutput, expectedCount: recommendations.count)
        guard !decisions.isEmpty else {
            return recommendations
        }

        let approved = recommendations.enumerated().compactMap { index, recommendation -> RecommendationItem? in
            let decision = decisions[index] ?? true
            return decision ? recommendation : nil
        }

        if !approved.isEmpty {
            return approved
        }

        // Keep at least one recommendation to avoid empty Home sections.
        return Array(recommendations.prefix(1))
    }

    private static func parseDecisions(from rawOutput: String, expectedCount: Int) -> [Int: Bool] {
        let candidates = [rawOutput, extractJSONObject(from: rawOutput)].compactMap { $0 }

        for candidate in candidates {
            if let parsed = decodeJSONDecisions(candidate, expectedCount: expectedCount), !parsed.isEmpty {
                return parsed
            }
        }

        return [:]
    }

    private static func decodeJSONDecisions(_ json: String, expectedCount: Int) -> [Int: Bool]? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(RecommendationReviewEnvelope.self, from: data) {
            return mapDecisions(envelope.items, expectedCount: expectedCount)
        }

        if let items = try? decoder.decode([RecommendationReviewItem].self, from: data) {
            return mapDecisions(items, expectedCount: expectedCount)
        }

        return nil
    }

    private static func mapDecisions(_ items: [RecommendationReviewItem], expectedCount: Int) -> [Int: Bool] {
        var byIndex: [Int: Bool] = [:]
        for item in items {
            guard item.index >= 1, item.index <= expectedCount else { continue }
            byIndex[item.index - 1] = item.ok
        }
        return byIndex
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}") else { return nil }
        guard first <= last else { return nil }
        return String(text[first...last])
    }
}

private struct RecommendationReviewEnvelope: Decodable {
    let items: [RecommendationReviewItem]
}

private struct RecommendationReviewItem: Decodable {
    let index: Int
    let ok: Bool
    let reason: String?
}
