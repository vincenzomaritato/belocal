import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct FeedbackTranslationInput: Sendable {
    let id: UUID
    let text: String
    let tags: [String]
}

struct FeedbackTranslationContent: Sendable {
    let text: String
    let tags: [String]
}

protocol FeedbackTranslationServing {
    func translate(
        feedbacks: [FeedbackTranslationInput],
        targetLanguage: String,
        languageCode: String
    ) async -> [UUID: FeedbackTranslationContent]
}

struct PassthroughFeedbackTranslationService: FeedbackTranslationServing {
    func translate(
        feedbacks: [FeedbackTranslationInput],
        targetLanguage: String,
        languageCode: String
    ) async -> [UUID: FeedbackTranslationContent] {
        Dictionary(uniqueKeysWithValues: feedbacks.map {
            ($0.id, FeedbackTranslationContent(text: $0.text, tags: $0.tags))
        })
    }
}

actor FeedbackTranslationCache {
    private var storage: [String: FeedbackTranslationContent] = [:]

    func value(for key: String) -> FeedbackTranslationContent? {
        storage[key]
    }

    func insert(_ value: FeedbackTranslationContent, for key: String) {
        storage[key] = value
    }
}

struct FoundationModelsFeedbackTranslationService: FeedbackTranslationServing {
    private let cache = FeedbackTranslationCache()

    func translate(
        feedbacks: [FeedbackTranslationInput],
        targetLanguage: String,
        languageCode: String
    ) async -> [UUID: FeedbackTranslationContent] {
        guard !feedbacks.isEmpty else { return [:] }

        var resolved: [UUID: FeedbackTranslationContent] = [:]
        var pending: [IndexedFeedbackTranslationInput] = []

        for (index, feedback) in feedbacks.enumerated() {
            let cacheKey = cacheKey(for: feedback, languageCode: languageCode)
            if let cached = await cache.value(for: cacheKey) {
                resolved[feedback.id] = cached
            } else {
                pending.append(
                    IndexedFeedbackTranslationInput(
                        index: index + 1,
                        id: feedback.id,
                        text: feedback.text,
                        tags: feedback.tags
                    )
                )
            }
        }

        guard !pending.isEmpty else { return resolved }

#if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(
                to: prompt(for: pending, targetLanguage: targetLanguage)
            )
            let translated = mergeTranslations(
                from: responseContent(from: response),
                pending: pending
            )

            for item in pending {
                let content = translated[item.id] ?? FeedbackTranslationContent(text: item.text, tags: item.tags)
                resolved[item.id] = content
                await cache.insert(content, for: cacheKey(for: item, languageCode: languageCode))
            }
        } catch {
            for item in pending {
                let original = FeedbackTranslationContent(text: item.text, tags: item.tags)
                resolved[item.id] = original
                await cache.insert(original, for: cacheKey(for: item, languageCode: languageCode))
            }
        }
#else
        for item in pending {
            let original = FeedbackTranslationContent(text: item.text, tags: item.tags)
            resolved[item.id] = original
            await cache.insert(original, for: cacheKey(for: item, languageCode: languageCode))
        }
#endif

        return resolved
    }

    private func prompt(for feedbacks: [IndexedFeedbackTranslationInput], targetLanguage: String) -> String {
        let payload = FeedbackTranslationPromptPayload(
            items: feedbacks.map {
                FeedbackTranslationPromptItem(index: $0.index, text: $0.text, tags: $0.tags)
            }
        )
        let encodedPayload = (try? JSONEncoder().encode(payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"items\":[]}"

        return """
        You translate travel feedback into \(targetLanguage).
        Translate each item faithfully into the target language.
        Preserve meaning, tone, sentiment, and brevity.
        Keep city names, country names, and proper nouns unchanged.
        If an item is already in the target language, keep it natural without adding detail.
        Translate tags too, but keep them short.

        Input JSON:
        \(encodedPayload)

        Return ONLY valid JSON in this exact shape:
        {"items":[{"index":1,"text":"...", "tags":["..."]}]}

        Rules:
        - include exactly \(feedbacks.count) items
        - index is 1-based
        - keep every translated text as a single plain string
        - do not add markdown, notes, or explanations
        """
    }

    private func mergeTranslations(
        from rawOutput: String,
        pending: [IndexedFeedbackTranslationInput]
    ) -> [UUID: FeedbackTranslationContent] {
        let translatedByIndex = parseTranslations(from: rawOutput, expectedCount: pending.count)
        var result: [UUID: FeedbackTranslationContent] = [:]

        for item in pending {
            let translated = translatedByIndex[item.index]
            result[item.id] = FeedbackTranslationContent(
                text: translated?.text?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? item.text,
                tags: translated?.tags.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? item.tags
            )
        }

        return result
    }

    private func parseTranslations(
        from rawOutput: String,
        expectedCount: Int
    ) -> [Int: ParsedFeedbackTranslation] {
        let candidates = [rawOutput, extractJSONObject(from: rawOutput)].compactMap { $0 }

        for candidate in candidates {
            if let parsed = decodeEnvelope(candidate, expectedCount: expectedCount), !parsed.isEmpty {
                return parsed
            }
        }

        return [:]
    }

    private func decodeEnvelope(_ rawJSON: String, expectedCount: Int) -> [Int: ParsedFeedbackTranslation]? {
        guard let data = rawJSON.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()

        if let envelope = try? decoder.decode(FeedbackTranslationResponseEnvelope.self, from: data) {
            return mapTranslations(envelope.items, expectedCount: expectedCount)
        }

        if let items = try? decoder.decode([FeedbackTranslationResponseItem].self, from: data) {
            return mapTranslations(items, expectedCount: expectedCount)
        }

        return nil
    }

    private func mapTranslations(
        _ items: [FeedbackTranslationResponseItem],
        expectedCount: Int
    ) -> [Int: ParsedFeedbackTranslation] {
        var result: [Int: ParsedFeedbackTranslation] = [:]

        for item in items {
            let zeroBasedIndex = item.index - 1
            guard (0..<expectedCount).contains(zeroBasedIndex) else { continue }
            result[item.index] = ParsedFeedbackTranslation(text: item.text, tags: item.tags)
        }

        return result
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

    private func extractJSONObject(from raw: String) -> String? {
        guard let start = raw.firstIndex(of: "{"),
              let end = raw.lastIndex(of: "}") else { return nil }
        return String(raw[start...end])
    }

    private func cacheKey(for feedback: FeedbackTranslationInput, languageCode: String) -> String {
        "\(languageCode)|\(feedback.id.uuidString)|\(feedback.text)|\(feedback.tags.joined(separator: "||"))"
    }

    private func cacheKey(for feedback: IndexedFeedbackTranslationInput, languageCode: String) -> String {
        "\(languageCode)|\(feedback.id.uuidString)|\(feedback.text)|\(feedback.tags.joined(separator: "||"))"
    }
}

private struct IndexedFeedbackTranslationInput: Sendable {
    let index: Int
    let id: UUID
    let text: String
    let tags: [String]
}

private struct FeedbackTranslationPromptPayload: Encodable {
    let items: [FeedbackTranslationPromptItem]
}

private struct FeedbackTranslationPromptItem: Encodable {
    let index: Int
    let text: String
    let tags: [String]
}

private struct FeedbackTranslationResponseEnvelope: Decodable {
    let items: [FeedbackTranslationResponseItem]
}

private struct FeedbackTranslationResponseItem: Decodable {
    let index: Int
    let text: String?
    let tags: [String]
}

private struct ParsedFeedbackTranslation {
    let text: String?
    let tags: [String]
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
