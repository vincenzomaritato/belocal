import Foundation
import SwiftData

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var authUserId: String
    var name: String
    // Persistent defaults allow lightweight migration when these fields are added later.
    var homeCity: String = ""
    var homeCountry: String = ""
    var budgetMin: Double
    var budgetMax: Double
    var preferredSeasonsJSON: String
    var travelStyleWeightsJSON: String
    var ecoSensitivity: Double
    var peopleDefault: Int
    var homeLatitude: Double = TravelDistanceCalculator.defaultHomeLatitude
    var homeLongitude: Double = TravelDistanceCalculator.defaultHomeLongitude

    init(
        id: UUID = UUID(),
        authUserId: String = "",
        name: String,
        homeCity: String = "",
        homeCountry: String = "",
        budgetMin: Double,
        budgetMax: Double,
        preferredSeasons: [String],
        travelStyleWeights: [String: Double],
        ecoSensitivity: Double,
        peopleDefault: Int,
        homeLatitude: Double = TravelDistanceCalculator.defaultHomeLatitude,
        homeLongitude: Double = TravelDistanceCalculator.defaultHomeLongitude
    ) {
        self.id = id
        self.authUserId = authUserId
        self.name = name
        self.homeCity = homeCity
        self.homeCountry = homeCountry
        self.budgetMin = budgetMin
        self.budgetMax = budgetMax
        self.preferredSeasonsJSON = CodableStorage.encode(preferredSeasons, fallback: "[]")
        self.travelStyleWeightsJSON = CodableStorage.encode(travelStyleWeights, fallback: "{}")
        self.ecoSensitivity = ecoSensitivity
        self.peopleDefault = peopleDefault
        self.homeLatitude = Swift.min(Swift.max(homeLatitude, -90), 90)
        self.homeLongitude = Swift.min(Swift.max(homeLongitude, -180), 180)
    }

    var preferredSeasons: [String] {
        get { CodableStorage.decode(preferredSeasonsJSON, as: [String].self, fallback: []) }
        set { preferredSeasonsJSON = CodableStorage.encode(newValue, fallback: "[]") }
    }

    var travelStyleWeights: [String: Double] {
        get { CodableStorage.decode(travelStyleWeightsJSON, as: [String: Double].self, fallback: [:]) }
        set { travelStyleWeightsJSON = CodableStorage.encode(newValue, fallback: "{}") }
    }

    var homeLocationLabel: String {
        let city = homeCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let country = homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        let joined = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
        return joined.isEmpty ? L10n.tr("Not set") : joined
    }
}
