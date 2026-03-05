import Foundation
import SwiftData

enum SwiftDataStack {
    static let schema = Schema([
        UserProfile.self,
        Destination.self,
        Trip.self,
        TravelerFeedback.self,
        LocalInsight.self,
        ActivityItem.self,
        SyncOperation.self,
        PlannerConversation.self
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            assertionFailure("Unable to create ModelContainer: \(error)")
            do {
                // Last-resort fallback: avoid a hard crash by creating an in-memory store.
                let fallbackConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                preconditionFailure("Unable to create any ModelContainer: \(error)")
            }
        }
    }
}
