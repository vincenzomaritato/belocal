import Foundation

struct FeedbackLocationOption: Identifiable, Hashable {
    let tripId: UUID
    let destinationId: UUID
    let destinationName: String
    let country: String
    let destinationLatitude: Double
    let destinationLongitude: Double
    let sourceType: FeedbackSourceType
    let authorHomeCity: String
    let authorHomeCountry: String
    let periodLabel: String

    var id: UUID { tripId }

    var authorHomeLabel: String {
        [authorHomeCity, authorHomeCountry]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var perspectiveLabel: String {
        switch sourceType {
        case .local:
            let destination = destinationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !destination.isEmpty {
                return L10n.f("Local in %@", destination)
            }
            if !authorHomeLabel.isEmpty {
                return L10n.f("Local in %@", authorHomeLabel)
            }
            return L10n.tr("Local")
        case .traveler:
            if !authorHomeLabel.isEmpty {
                return L10n.f("Traveler from %@", authorHomeLabel)
            }
            return L10n.tr("Traveler")
        }
    }
}
