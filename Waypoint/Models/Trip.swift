import Foundation
import SwiftData

enum TransportType: String, Codable, CaseIterable {
    case plane
    case train
    case car

    var localizedTitle: String {
        switch self {
        case .plane: return L10n.tr("Plane")
        case .train: return L10n.tr("Train")
        case .car: return L10n.tr("Car")
        }
    }

    var iconName: String {
        switch self {
        case .plane: return "airplane"
        case .train: return "tram.fill"
        case .car: return "car.fill"
        }
    }
}

enum TripIntent: String, Codable, CaseIterable {
    case been
    case wantToGo

    static func inferred(startDate: Date, endDate: Date, now: Date = .now) -> TripIntent {
        let referenceDate = max(startDate, endDate)
        return referenceDate > now ? .wantToGo : .been
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
    var tripIntentRaw: String = TripIntent.been.rawValue
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
        tripIntent: TripIntent? = nil,
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
        self.tripIntentRaw = (tripIntent ?? TripIntent.inferred(startDate: startDate, endDate: endDate)).rawValue
        self.people = people
        self.budgetSpent = budgetSpent
        self.co2Estimated = co2Estimated
        self.ecoScoreSnapshot = ecoScoreSnapshot
    }

    var transportType: TransportType {
        get { TransportType(rawValue: transportTypeRaw) ?? .plane }
        set { transportTypeRaw = newValue.rawValue }
    }

    var tripIntent: TripIntent {
        get {
            if TripIntent(rawValue: tripIntentRaw) == .wantToGo {
                return .wantToGo
            }
            return TripIntent.inferred(startDate: startDate, endDate: endDate)
        }
        set { tripIntentRaw = newValue.rawValue }
    }
}
