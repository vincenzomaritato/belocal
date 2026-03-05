import Foundation
import SwiftData

enum SyncOperationType: String, Codable, CaseIterable {
    case createFeedback
    case updateFeedback
    case deleteFeedback
    case createTrip
    case deleteTrip
    case saveActivities
    case deleteActivity
    case upsertProfile
}

enum SyncOperationStatus: String, Codable, CaseIterable {
    case pending
    case syncing
    case synced
    case failed
}

@Model
final class SyncOperation {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var payloadJSON: String
    var createdAt: Date
    var statusRaw: String
    var retryCount: Int
    var lastError: String?

    init(
        id: UUID = UUID(),
        type: SyncOperationType,
        payloadJSON: String,
        createdAt: Date = .now,
        status: SyncOperationStatus = .pending,
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.statusRaw = status.rawValue
        self.retryCount = retryCount
        self.lastError = lastError
    }

    var type: SyncOperationType {
        get { SyncOperationType(rawValue: typeRaw) ?? .createTrip }
        set { typeRaw = newValue.rawValue }
    }

    var status: SyncOperationStatus {
        get { SyncOperationStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}
