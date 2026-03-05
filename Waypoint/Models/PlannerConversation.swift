import Foundation
import SwiftData

@Model
final class PlannerConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var snapshotJSON: String
    var lastMessagePreview: String
    var destinationHint: String?
    var hasFinalBrief: Bool
    var finalBriefHeadline: String?
    var finalBriefOverview: String?
    var linkedTripId: UUID?

    init(
        id: UUID = UUID(),
        title: String = "New chat",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        snapshotJSON: String = "",
        lastMessagePreview: String = "",
        destinationHint: String? = nil,
        hasFinalBrief: Bool = false,
        finalBriefHeadline: String? = nil,
        finalBriefOverview: String? = nil,
        linkedTripId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.snapshotJSON = snapshotJSON
        self.lastMessagePreview = lastMessagePreview
        self.destinationHint = destinationHint
        self.hasFinalBrief = hasFinalBrief
        self.finalBriefHeadline = finalBriefHeadline
        self.finalBriefOverview = finalBriefOverview
        self.linkedTripId = linkedTripId
    }
}

