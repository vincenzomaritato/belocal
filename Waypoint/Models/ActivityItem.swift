import Foundation
import SwiftData

enum ActivityType: String, Codable, CaseIterable {
    case restaurant
    case activity
    case flight
    case brief
}

@Model
final class ActivityItem {
    @Attribute(.unique) var id: UUID
    var tripId: UUID
    var typeRaw: String
    var title: String
    var note: String
    var externalId: String?
    var metaJSON: String?

    init(
        id: UUID = UUID(),
        tripId: UUID,
        type: ActivityType,
        title: String,
        note: String,
        externalId: String? = nil,
        metaJSON: String? = nil
    ) {
        self.id = id
        self.tripId = tripId
        self.typeRaw = type.rawValue
        self.title = title
        self.note = note
        self.externalId = externalId
        self.metaJSON = metaJSON
    }

    var type: ActivityType {
        get { ActivityType(rawValue: typeRaw) ?? .activity }
        set { typeRaw = newValue.rawValue }
    }
}
