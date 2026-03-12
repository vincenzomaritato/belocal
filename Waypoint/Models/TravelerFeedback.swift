import Foundation
import SwiftData

enum FeedbackSourceType: String, Codable, CaseIterable {
    case traveler
    case local

    var title: String {
        switch self {
        case .traveler: return L10n.tr("Traveler")
        case .local: return L10n.tr("Local")
        }
    }

    var symbol: String {
        switch self {
        case .traveler: return "airplane"
        case .local: return "house.fill"
        }
    }

    var destinationSentencePrefix: String {
        switch self {
        case .traveler: return L10n.tr("Traveler from")
        case .local: return L10n.tr("Local in")
        }
    }
}

@Model
final class TravelerFeedback {
    @Attribute(.unique) var id: UUID
    var tripId: UUID
    var destinationId: UUID?
    var destinationName: String
    var destinationCountry: String
    var rating: Int
    var tagsJSON: String
    var text: String
    var crowding: Double
    var value: Double
    var sustainabilityPerception: Double
    var sourceTypeRaw: String
    var authorHomeCity: String?
    var authorHomeCountry: String?
    var sentiment: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        tripId: UUID,
        destinationId: UUID? = nil,
        destinationName: String = "",
        destinationCountry: String = "",
        rating: Int,
        tags: [String],
        text: String,
        crowding: Double,
        value: Double,
        sustainabilityPerception: Double,
        sourceType: FeedbackSourceType = .traveler,
        authorHomeCity: String? = nil,
        authorHomeCountry: String? = nil,
        sentiment: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.tripId = tripId
        self.destinationId = destinationId
        self.destinationName = destinationName
        self.destinationCountry = destinationCountry
        self.rating = rating
        self.tagsJSON = CodableStorage.encode(tags, fallback: "[]")
        self.text = text
        self.crowding = crowding
        self.value = value
        self.sustainabilityPerception = sustainabilityPerception
        self.sourceTypeRaw = sourceType.rawValue
        self.authorHomeCity = authorHomeCity
        self.authorHomeCountry = authorHomeCountry
        self.sentiment = sentiment
        self.createdAt = createdAt
    }

    var tags: [String] {
        get { CodableStorage.decode(tagsJSON, as: [String].self, fallback: []) }
        set { tagsJSON = CodableStorage.encode(newValue, fallback: "[]") }
    }

    var sourceType: FeedbackSourceType {
        get { FeedbackSourceType(rawValue: sourceTypeRaw) ?? .traveler }
        set { sourceTypeRaw = newValue.rawValue }
    }

    var authorHomeLabel: String {
        [authorHomeCity, authorHomeCountry]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var perspectiveLabel: String {
        switch sourceType {
        case .local:
            let destination = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !destination.isEmpty {
                return L10n.f("%@ %@", sourceType.destinationSentencePrefix, destination)
            }
            if !authorHomeLabel.isEmpty {
                return L10n.f("%@ %@", sourceType.destinationSentencePrefix, authorHomeLabel)
            }
            return L10n.tr("Local perspective")
        case .traveler:
            if !authorHomeLabel.isEmpty {
                return L10n.f("%@ %@", sourceType.destinationSentencePrefix, authorHomeLabel)
            }
            return L10n.tr("Traveler perspective")
        }
    }
}
