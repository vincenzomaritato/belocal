import Foundation
import SwiftData

@Model
final class LocalInsight {
    @Attribute(.unique) var id: UUID
    var destinationId: UUID
    var sustainabilityScore: Double
    var authenticityScore: Double
    var overcrowdingScore: Double
    var summaryText: String

    init(
        id: UUID = UUID(),
        destinationId: UUID,
        sustainabilityScore: Double,
        authenticityScore: Double,
        overcrowdingScore: Double,
        summaryText: String
    ) {
        self.id = id
        self.destinationId = destinationId
        self.sustainabilityScore = sustainabilityScore
        self.authenticityScore = authenticityScore
        self.overcrowdingScore = overcrowdingScore
        self.summaryText = summaryText
    }
}
