import Foundation

struct OpenAIChatReply: Sendable {
    let responseID: String
    let text: String
}

enum OpenAIChatServiceError: LocalizedError {
    case missingAPIKey
    case httpStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OPENAI_API_KEY is not configured."
        case .httpStatus(let code, let message):
            return "OpenAI API error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid OpenAI response."
        }
    }
}

protocol OpenAIChatServing {
    func send(userMessage: String, previousResponseID: String?) async throws -> OpenAIChatReply
    func stream(
        userMessage: String,
        previousResponseID: String?,
        onDelta: @escaping (String) async -> Void
    ) async throws -> OpenAIChatReply
}

struct OpenAIChatService: OpenAIChatServing {
    let config: TravelAPIConfig
    let session: URLSession
    private let assistantInstructions = """
    You are Waypoint, a premium AI travel planner.
    You can only discuss travel: destinations, itineraries, attractions, logistics, budget, food, safety, seasons, and bookings.
    If the user asks for non-travel topics, refuse briefly and redirect to travel planning.
    Respond only in English.
    Always format responses as valid Markdown (GitHub-flavored) with clear sections.
    Be concise, practical, and context-aware.
    """

    init(config: TravelAPIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func send(userMessage: String, previousResponseID: String?) async throws -> OpenAIChatReply {
        guard config.hasOpenAI else {
            throw OpenAIChatServiceError.missingAPIKey
        }

        let payload = CreateResponseRequest(
            model: config.openAIModel,
            instructions: assistantInstructions,
            input: [
                .init(role: "user", content: [.init(text: userMessage)])
            ],
            previousResponseID: previousResponseID,
            stream: false
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIChatServiceError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            let apiError = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data)
            throw OpenAIChatServiceError.httpStatus(http.statusCode, apiError?.error.message ?? "Request failed")
        }

        let decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        let text = decoded.output
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
            .filter { $0.type == "output_text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw OpenAIChatServiceError.invalidResponse
        }

        return OpenAIChatReply(responseID: decoded.id, text: text)
    }

    func stream(
        userMessage: String,
        previousResponseID: String?,
        onDelta: @escaping (String) async -> Void
    ) async throws -> OpenAIChatReply {
        guard config.hasOpenAI else {
            throw OpenAIChatServiceError.missingAPIKey
        }

        let payload = CreateResponseRequest(
            model: config.openAIModel,
            instructions: assistantInstructions,
            input: [
                .init(role: "user", content: [.init(text: userMessage)])
            ],
            previousResponseID: previousResponseID,
            stream: true
        )

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIChatServiceError.invalidResponse
        }

        if !(200..<300).contains(http.statusCode) {
            let data = try await collectData(from: bytes)
            let apiError = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data)
            throw OpenAIChatServiceError.httpStatus(http.statusCode, apiError?.error.message ?? "Request failed")
        }

        var collectedText = ""
        var finalResponseID: String?
        var completedResponseText: String?

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }

            let payloadString = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            if payloadString == "[DONE]" {
                break
            }

            guard let data = payloadString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if finalResponseID == nil {
                if let responseObject = json["response"] as? [String: Any],
                   let id = responseObject["id"] as? String {
                    finalResponseID = id
                } else if let id = json["response_id"] as? String {
                    finalResponseID = id
                }
            }

            if completedResponseText == nil,
               let responseObject = json["response"] as? [String: Any] {
                completedResponseText = extractResponseText(from: responseObject)
            }

            if let delta = extractDeltaText(from: json), !delta.isEmpty {
                collectedText += delta
                await onDelta(delta)
            }
        }

        let normalizedText = collectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedText.isEmpty {
            return OpenAIChatReply(
                responseID: finalResponseID ?? (previousResponseID ?? UUID().uuidString),
                text: normalizedText
            )
        }

        let normalizedCompletedText = completedResponseText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalizedCompletedText.isEmpty {
            return OpenAIChatReply(
                responseID: finalResponseID ?? (previousResponseID ?? UUID().uuidString),
                text: normalizedCompletedText
            )
        }

        // Last-resort fallback for providers that emit no parsable text in stream mode.
        do {
            return try await send(
                userMessage: userMessage,
                previousResponseID: previousResponseID
            )
        } catch {
            // Fallback to non-streaming to avoid losing the assistant answer when
            // providers emit only final payloads without deltas.
            let fallbackErrorText = "I cannot stream the answer right now. \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
            return OpenAIChatReply(
                responseID: finalResponseID ?? (previousResponseID ?? UUID().uuidString),
                text: fallbackErrorText
            )
        }
    }

    private func extractResponseText(from responseObject: [String: Any]) -> String? {
        if let outputText = responseObject["output_text"] as? String {
            return outputText
        }

        if let outputTextArray = responseObject["output_text"] as? [Any] {
            let fragments = outputTextArray.compactMap { entry -> String? in
                if let text = entry as? String {
                    return text
                }
                if let object = entry as? [String: Any] {
                    if let text = object["text"] as? String {
                        return text
                    }
                    if let textObject = object["text"] as? [String: Any],
                       let value = textObject["value"] as? String {
                        return value
                    }
                    if let value = object["value"] as? String {
                        return value
                    }
                }
                return nil
            }
            let merged = fragments.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !merged.isEmpty {
                return merged
            }
        }

        guard let output = responseObject["output"] as? [[String: Any]] else {
            return nil
        }

        let textParts = output
            .filter { ($0["type"] as? String) == "message" }
            .flatMap { item -> [[String: Any]] in
                item["content"] as? [[String: Any]] ?? []
            }
            .compactMap { contentItem -> String? in
                guard (contentItem["type"] as? String) == "output_text" else { return nil }
                if let text = contentItem["text"] as? String {
                    return text
                }
                if let textObject = contentItem["text"] as? [String: Any],
                   let value = textObject["value"] as? String {
                    return value
                }
                return nil
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return textParts.isEmpty ? nil : textParts
    }

    private func extractDeltaText(from json: [String: Any]) -> String? {
        if let eventType = json["type"] as? String,
           eventType == "response.output_text.delta",
           let delta = json["delta"] as? String {
            return delta
        }

        if let direct = json["delta"] as? String {
            return direct
        }

        if let deltaObject = json["delta"] as? [String: Any],
           let deltaText = deltaObject["text"] as? String {
            return deltaText
        }

        if let deltaObject = json["delta"] as? [String: Any],
           let value = deltaObject["value"] as? String {
            return value
        }

        if let content = json["content"] as? [String: Any] {
            if let text = content["text"] as? String {
                return text
            }
            if let textObject = content["text"] as? [String: Any],
               let value = textObject["value"] as? String {
                return value
            }
        }

        if let outputText = json["output_text"] as? String {
            return outputText
        }

        return nil
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }
}

private struct CreateResponseRequest: Encodable {
    let model: String
    let instructions: String
    let input: [InputMessage]
    let previousResponseID: String?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case previousResponseID = "previous_response_id"
        case stream
    }

    struct InputMessage: Encodable {
        let type: String = "message"
        let role: String
        let content: [InputContent]
    }

    struct InputContent: Encodable {
        let type: String = "input_text"
        let text: String
    }
}

private struct OpenAIResponseEnvelope: Decodable {
    struct OutputItem: Decodable {
        let type: String
        let content: [OutputContent]?
    }

    struct OutputContent: Decodable {
        let type: String
        let text: String?
    }

    let id: String
    let output: [OutputItem]
}

private struct OpenAIAPIErrorEnvelope: Decodable {
    struct APIErrorBody: Decodable {
        let message: String
    }

    let error: APIErrorBody
}
