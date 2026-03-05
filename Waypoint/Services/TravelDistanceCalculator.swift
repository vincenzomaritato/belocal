import Foundation

enum TravelDistanceCalculator {
    static let defaultHomeLatitude = 41.9028
    static let defaultHomeLongitude = 12.4964

    static func homeCoordinate(from profile: UserProfile?) -> (latitude: Double, longitude: Double) {
        guard let profile else {
            return (defaultHomeLatitude, defaultHomeLongitude)
        }
        return (
            latitude: clamp(profile.homeLatitude, min: -90, max: 90),
            longitude: clamp(profile.homeLongitude, min: -180, max: 180)
        )
    }

    static func distanceKm(from origin: (latitude: Double, longitude: Double), to destination: (latitude: Double, longitude: Double)) -> Double {
        haversineDistanceKm(
            from: (clamp(origin.latitude, min: -90, max: 90), clamp(origin.longitude, min: -180, max: 180)),
            to: (clamp(destination.latitude, min: -90, max: 90), clamp(destination.longitude, min: -180, max: 180))
        )
    }

    static func distanceKm(from profile: UserProfile?, to destination: Destination) -> Double {
        distanceKm(
            from: homeCoordinate(from: profile),
            to: (destination.latitude, destination.longitude)
        )
    }

    private static func haversineDistanceKm(from: (Double, Double), to: (Double, Double)) -> Double {
        let earthRadiusKm = 6_371.0
        let lat1 = from.0 * .pi / 180
        let lon1 = from.1 * .pi / 180
        let lat2 = to.0 * .pi / 180
        let lon2 = to.1 * .pi / 180

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return max(0, earthRadiusKm * c)
    }

    private static func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }
}
