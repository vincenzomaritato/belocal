import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
protocol ExplorerBriefServing {
    func makeBrief(
        city: ExplorerCity,
        wikiInfo: CityWikiInfo?,
        attractions: [CityPlace],
        restaurants: [CityPlace],
        essentials: [CityPlace],
        userProfile: UserProfile?,
        feedback: [TravelerFeedback],
        destination: Destination?,
        localInsight: LocalInsight?
    ) async -> String?
}

struct FoundationModelsExplorerBriefService: ExplorerBriefServing {
    func makeBrief(
        city: ExplorerCity,
        wikiInfo: CityWikiInfo?,
        attractions: [CityPlace],
        restaurants: [CityPlace],
        essentials: [CityPlace],
        userProfile: UserProfile?,
        feedback: [TravelerFeedback],
        destination: Destination?,
        localInsight: LocalInsight?
    ) async -> String? {
        let fallback = fallbackBrief(
            city: city,
            attractions: attractions,
            restaurants: restaurants,
            essentials: essentials,
            userProfile: userProfile,
            feedback: feedback,
            destination: destination
        )

#if canImport(FoundationModels)
        do {
            let prompt = buildPrompt(
                city: city,
                wikiInfo: wikiInfo,
                attractions: attractions,
                restaurants: restaurants,
                essentials: essentials,
                userProfile: userProfile,
                feedback: feedback,
                destination: destination,
                localInsight: localInsight
            )
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let content = responseContent(from: response)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? fallback : content
        } catch {
            return fallback
        }
#else
        return fallback
#endif
    }

    private func buildPrompt(
        city: ExplorerCity,
        wikiInfo: CityWikiInfo?,
        attractions: [CityPlace],
        restaurants: [CityPlace],
        essentials: [CityPlace],
        userProfile: UserProfile?,
        feedback: [TravelerFeedback],
        destination: Destination?,
        localInsight: LocalInsight?
    ) -> String {
        let topAttractions = attractions.prefix(3).map(\.name).joined(separator: ", ")
        let topRestaurants = restaurants.prefix(3).map(\.name).joined(separator: ", ")
        let profileStyles = topStyles(from: userProfile).joined(separator: ", ")
        let avgRating = feedback.isEmpty
            ? "n/a"
            : String(format: "%.1f/5", Double(feedback.map(\.rating).reduce(0, +)) / Double(feedback.count))

        return """
        You are a travel assistant for an Apple-style city explorer app.
        Write a concise personalized brief in English, max 2 short sentences.
        Tone: practical, premium, specific.

        City: \(city.label)
        Wikipedia summary excerpt: \(wikiInfo?.summary.prefix(280) ?? "n/a")
        Top attractions: \(topAttractions.isEmpty ? "n/a" : topAttractions)
        Top restaurants: \(topRestaurants.isEmpty ? "n/a" : topRestaurants)
        Essentials count: \(essentials.count)
        User preferred styles: \(profileStyles.isEmpty ? "n/a" : profileStyles)
        User budget range EUR: \(Int(userProfile?.budgetMin ?? 0))-\(Int(userProfile?.budgetMax ?? 0))
        User eco sensitivity: \(String(format: "%.2f", userProfile?.ecoSensitivity ?? 0))
        Traveler average rating for destination: \(avgRating)
        Local destination climate: \(destination?.climate ?? "n/a")
        Local destination eco score: \(destination?.ecoScore ?? 0)
        Local destination crowding: \(destination?.crowdingIndex ?? 0)
        Local insight summary: \(localInsight?.summaryText ?? "n/a")

        Output only the brief text, no bullets, no markdown.
        """
    }

    private func fallbackBrief(
        city: ExplorerCity,
        attractions: [CityPlace],
        restaurants: [CityPlace],
        essentials: [CityPlace],
        userProfile: UserProfile?,
        feedback: [TravelerFeedback],
        destination: Destination?
    ) -> String {
        let styleLine: String
        if let topStyle = topStyles(from: userProfile).first {
            styleLine = "Top match for your \(topStyle.lowercased()) style."
        } else {
            styleLine = "Balanced mix for a first visit."
        }

        let ratingLine: String
        if feedback.isEmpty {
            ratingLine = "No local feedback yet, so results are based on live place quality signals."
        } else {
            let avg = Double(feedback.map(\.rating).reduce(0, +)) / Double(feedback.count)
            ratingLine = "Traveler feedback averages \(String(format: "%.1f", avg))/5."
        }

        let climatePart = destination.map { "Climate: \($0.climate)." } ?? ""
        return "\(city.name) has \(attractions.count) attractions, \(restaurants.count) restaurants, and \(essentials.count) essentials. \(styleLine) \(ratingLine) \(climatePart)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func topStyles(from profile: UserProfile?) -> [String] {
        guard let profile else { return [] }
        return profile.travelStyleWeights
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .prefix(3)
            .map(\.key)
    }

    private func responseContent<T>(from response: T) -> String {
        let mirror = Mirror(reflecting: response)
        for child in mirror.children {
            guard child.label == "content" else { continue }
            if let text = child.value as? String {
                return text
            }
        }
        return String(describing: response)
    }
}
