import Foundation

struct FeedbackAudienceResolver {
    static let localDistanceThresholdKm: Double = 80

    static func sourceType(
        userProfile: UserProfile?,
        destinationName: String,
        destinationCountry: String,
        destinationCoordinate: (latitude: Double, longitude: Double)?
    ) -> FeedbackSourceType {
        guard let userProfile else { return .traveler }

        let homeCity = normalized(userProfile.homeCity)
        let homeCountry = normalized(userProfile.homeCountry)

        let targetCity = normalized(destinationName)
        let targetCountry = normalized(destinationCountry)

        if !homeCity.isEmpty,
           !homeCountry.isEmpty,
           homeCity == targetCity,
           homeCountry == targetCountry {
            return .local
        }

        if let destinationCoordinate {
            let distance = TravelDistanceCalculator.distanceKm(
                from: TravelDistanceCalculator.homeCoordinate(from: userProfile),
                to: destinationCoordinate
            )
            if distance <= localDistanceThresholdKm {
                return .local
            }
        }

        return .traveler
    }

    private static func normalized(_ text: String?) -> String {
        (text ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
