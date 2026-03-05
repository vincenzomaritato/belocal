import Foundation
import SwiftData

enum TransportType: String, Codable, CaseIterable {
    case plane
    case train
    case car

    var iconName: String {
        switch self {
        case .plane: return "airplane"
        case .train: return "tram.fill"
        case .car: return "car.fill"
        }
    }
}

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var destinationId: UUID
    var startDate: Date
    var endDate: Date
    var transportTypeRaw: String
    var people: Int
    var budgetSpent: Double
    var co2Estimated: Double
    var ecoScoreSnapshot: Double

    init(
        id: UUID = UUID(),
        userId: UUID,
        destinationId: UUID,
        startDate: Date,
        endDate: Date,
        transportType: TransportType,
        people: Int,
        budgetSpent: Double,
        co2Estimated: Double,
        ecoScoreSnapshot: Double
    ) {
        self.id = id
        self.userId = userId
        self.destinationId = destinationId
        self.startDate = startDate
        self.endDate = endDate
        self.transportTypeRaw = transportType.rawValue
        self.people = people
        self.budgetSpent = budgetSpent
        self.co2Estimated = co2Estimated
        self.ecoScoreSnapshot = ecoScoreSnapshot
    }

    var transportType: TransportType {
        get { TransportType(rawValue: transportTypeRaw) ?? .plane }
        set { transportTypeRaw = newValue.rawValue }
    }
}
