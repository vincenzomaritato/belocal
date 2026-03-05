import CoreLocation
import Foundation
import SwiftData

@Model
final class Destination {
    @Attribute(.unique) var id: UUID
    var name: String
    var country: String
    var latitude: Double
    var longitude: Double
    var stylesJSON: String
    var climate: String
    var costIndex: Double
    var ecoScore: Double
    var crowdingIndex: Double
    var typicalSeasonJSON: String
    var distanceKm: Double

    init(
        id: UUID = UUID(),
        name: String,
        country: String,
        latitude: Double,
        longitude: Double,
        styles: [String],
        climate: String,
        costIndex: Double,
        ecoScore: Double,
        crowdingIndex: Double,
        typicalSeason: [String],
        distanceKm: Double
    ) {
        self.id = id
        self.name = name
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.stylesJSON = CodableStorage.encode(styles, fallback: "[]")
        self.climate = climate
        self.costIndex = costIndex
        self.ecoScore = ecoScore
        self.crowdingIndex = crowdingIndex
        self.typicalSeasonJSON = CodableStorage.encode(typicalSeason, fallback: "[]")
        self.distanceKm = distanceKm
    }

    var styles: [String] {
        get { CodableStorage.decode(stylesJSON, as: [String].self, fallback: []) }
        set { stylesJSON = CodableStorage.encode(newValue, fallback: "[]") }
    }

    var typicalSeason: [String] {
        get { CodableStorage.decode(typicalSeasonJSON, as: [String].self, fallback: []) }
        set { typicalSeasonJSON = CodableStorage.encode(newValue, fallback: "[]") }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
