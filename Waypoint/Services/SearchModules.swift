import Foundation

struct SearchInput: Sendable {
    var query: String
    var budget: Double
    var people: Int
    var startDate: Date
    var endDate: Date
    var destinationName: String?
    var destinationCountry: String?
    var latitude: Double?
    var longitude: Double?
}

protocol SearchModule {
    associatedtype Result
    func search(_ input: SearchInput) async -> [Result]
}

struct FlightOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let airline: String
    let price: Double
    let durationHours: Double
}

struct RestaurantOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let cuisine: String
    let estimatedCost: Double
}

struct ActivityOption: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let category: String
    let estimatedCost: Double
}
