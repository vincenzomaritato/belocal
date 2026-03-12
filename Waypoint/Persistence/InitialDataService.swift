import Foundation
import SwiftData

@MainActor
final class InitialDataService {
    func prepare(context: ModelContext) throws {
        let hasProfile = try context.fetchCount(FetchDescriptor<UserProfile>()) > 0
        guard !hasProfile else { return }

        let profile = UserProfile(
            name: "Traveler",
            budgetMin: 1000,
            budgetMax: 3000,
            preferredSeasons: ["Spring", "Autumn"],
            travelStyleWeights: [
                "Culture": 0.3,
                "Food": 0.25,
                "Nature": 0.25,
                "Beach": 0.2
            ],
            ecoSensitivity: 0.7,
            peopleDefault: 2
        )
        context.insert(profile)
        try context.save()
    }

    func clearLocalData(context: ModelContext, recreateProfile: Bool = true) throws {
        try context.fetch(FetchDescriptor<SyncOperation>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<TravelerFeedback>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<ActivityItem>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Trip>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<LocalInsight>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Destination>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<UserProfile>()).forEach(context.delete)
        try context.save()

        if recreateProfile {
            try prepare(context: context)
        }
    }
}
