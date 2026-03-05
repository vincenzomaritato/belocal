import Foundation
import Observation
import SwiftData
import SwiftUI

struct FeedbackDraft {
    var selectedTripId: UUID?
    var rating: Int = 4
    var tags: Set<String> = []
    var text: String = ""
    var crowding: Double = 0.45
    var value: Double = 0.7
    var sustainabilityPerception: Double = 0.75
}

@MainActor
@Observable
final class TripDetailViewModel {
    let trip: Trip
    let destination: Destination?

    var activities: [ActivityItem] = []
    var feedbackEntries: [TravelerFeedback] = []
    var feedbackDraft = FeedbackDraft()

    var showFeedbackSheet = false
    var savingFeedback = false
    var feedbackError: String?
    var isUpdatingTrip = false
    var isDeletingTrip = false
    var tripMutationError: String?

    init(trip: Trip, destination: Destination?) {
        self.trip = trip
        self.destination = destination
    }

    func load(context: ModelContext) {
        let activityDescriptor = FetchDescriptor<ActivityItem>()
        let feedbackDescriptor = FetchDescriptor<TravelerFeedback>(sortBy: [SortDescriptor(\TravelerFeedback.createdAt, order: .reverse)])

        activities = ((try? context.fetch(activityDescriptor)) ?? []).filter { $0.tripId == trip.id }
        feedbackEntries = ((try? context.fetch(feedbackDescriptor)) ?? []).filter { $0.tripId == trip.id }
    }

    func saveFeedback(
        context: ModelContext,
        syncManager: SyncManager,
        selectedLocation: FeedbackLocationOption,
        onSaved: () -> Void
    ) {
        savingFeedback = true
        feedbackError = nil

        let sentiment: String
        if feedbackDraft.rating >= 4 {
            sentiment = "positive"
        } else if feedbackDraft.rating == 3 {
            sentiment = "neutral"
        } else {
            sentiment = "negative"
        }

        let feedback = TravelerFeedback(
            tripId: selectedLocation.tripId,
            destinationId: selectedLocation.destinationId,
            destinationName: selectedLocation.destinationName,
            destinationCountry: selectedLocation.country,
            rating: feedbackDraft.rating,
            tags: Array(feedbackDraft.tags).sorted(),
            text: feedbackDraft.text,
            crowding: feedbackDraft.crowding,
            value: feedbackDraft.value,
            sustainabilityPerception: feedbackDraft.sustainabilityPerception,
            sourceType: selectedLocation.sourceType,
            authorHomeCity: selectedLocation.authorHomeCity,
            authorHomeCountry: selectedLocation.authorHomeCountry,
            sentiment: sentiment,
            createdAt: .now
        )

        context.insert(feedback)
        syncManager.enqueue(
            type: .createFeedback,
            payload: [
                "feedbackId": feedback.id.uuidString,
                "tripId": selectedLocation.tripId.uuidString,
                "destinationId": selectedLocation.destinationId.uuidString,
                "destinationName": selectedLocation.destinationName,
                "destinationCountry": selectedLocation.country,
                "sourceType": selectedLocation.sourceType.rawValue,
                "authorHomeCity": selectedLocation.authorHomeCity,
                "authorHomeCountry": selectedLocation.authorHomeCountry,
                "rating": "\(feedbackDraft.rating)",
                "text": feedbackDraft.text,
                "tags": Array(feedbackDraft.tags).sorted().joined(separator: ","),
                "crowding": String(format: "%.4f", feedbackDraft.crowding),
                "value": String(format: "%.4f", feedbackDraft.value),
                "sustainabilityPerception": String(format: "%.4f", feedbackDraft.sustainabilityPerception),
                "sentiment": sentiment,
                "createdAt": ISO8601DateFormatter().string(from: feedback.createdAt)
            ],
            context: context
        )

        do {
            try context.save()
            if selectedLocation.tripId == trip.id {
                feedbackEntries.insert(feedback, at: 0)
            }
            savingFeedback = false
            showFeedbackSheet = false
            feedbackDraft = FeedbackDraft()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                onSaved()
            }
        } catch {
            savingFeedback = false
            feedbackError = "Failed to save feedback locally."
        }
    }

    func updateTrip(
        context: ModelContext,
        syncManager: SyncManager,
        startDate: Date,
        endDate: Date,
        transportType: TransportType,
        people: Int,
        budgetSpent: Double,
        co2Estimated: Double,
        ecoScoreSnapshot: Double,
        onSaved: () -> Void
    ) {
        isUpdatingTrip = true
        tripMutationError = nil

        trip.startDate = startDate
        trip.endDate = max(endDate, startDate)
        trip.transportType = transportType
        trip.people = max(1, people)
        trip.budgetSpent = max(0, budgetSpent)
        trip.co2Estimated = max(0, co2Estimated)
        trip.ecoScoreSnapshot = ecoScoreSnapshot

        var syncPayload: [String: String] = [
            "tripId": trip.id.uuidString,
            "userId": trip.userId.uuidString,
            "destinationId": trip.destinationId.uuidString,
            "startDate": ISO8601DateFormatter().string(from: trip.startDate),
            "endDate": ISO8601DateFormatter().string(from: trip.endDate),
            "transportType": trip.transportType.rawValue,
            "people": "\(trip.people)",
            "budgetSpent": String(format: "%.0f", trip.budgetSpent),
            "co2Estimated": String(format: "%.2f", trip.co2Estimated),
            "ecoScoreSnapshot": String(format: "%.4f", trip.ecoScoreSnapshot)
        ]
        if let destination {
            syncPayload["destinationName"] = destination.name
            syncPayload["destinationCountry"] = destination.country
            syncPayload["destinationLatitude"] = String(format: "%.6f", destination.latitude)
            syncPayload["destinationLongitude"] = String(format: "%.6f", destination.longitude)
            syncPayload["destinationDistanceKm"] = String(format: "%.3f", destination.distanceKm)
            syncPayload["destinationEcoScore"] = String(format: "%.3f", destination.ecoScore)
            syncPayload["destinationClimate"] = destination.climate
            syncPayload["destinationCostIndex"] = String(format: "%.3f", destination.costIndex)
            syncPayload["destinationCrowdingIndex"] = String(format: "%.3f", destination.crowdingIndex)
            syncPayload["destinationStylesJSON"] = CodableStorage.encode(destination.styles, fallback: "[]")
            syncPayload["destinationTypicalSeasonJSON"] = CodableStorage.encode(destination.typicalSeason, fallback: "[]")
        }
        syncManager.enqueue(type: .createTrip, payload: syncPayload, context: context)

        do {
            try context.save()
            load(context: context)
            isUpdatingTrip = false
            onSaved()
        } catch {
            isUpdatingTrip = false
            tripMutationError = "Could not update this trip."
        }
    }

    func deleteTrip(
        context: ModelContext,
        syncManager: SyncManager,
        onDeleted: () -> Void
    ) {
        isDeletingTrip = true
        tripMutationError = nil

        let tripID = trip.id

        let activities = (try? context.fetch(FetchDescriptor<ActivityItem>())) ?? []
        for activity in activities where activity.tripId == tripID {
            syncManager.enqueue(
                type: .deleteActivity,
                payload: ["activityId": activity.id.uuidString],
                context: context
            )
            context.delete(activity)
        }

        let feedbackEntries = (try? context.fetch(FetchDescriptor<TravelerFeedback>())) ?? []
        for feedback in feedbackEntries where feedback.tripId == tripID {
            syncManager.enqueue(
                type: .deleteFeedback,
                payload: ["feedbackId": feedback.id.uuidString],
                context: context
            )
            context.delete(feedback)
        }

        let conversations = (try? context.fetch(FetchDescriptor<PlannerConversation>())) ?? []
        for conversation in conversations where conversation.linkedTripId == tripID {
            conversation.linkedTripId = nil
        }

        syncManager.enqueue(
            type: .deleteTrip,
            payload: ["tripId": tripID.uuidString],
            context: context
        )
        context.delete(trip)

        do {
            try context.save()
            isDeletingTrip = false
            onDeleted()
        } catch {
            isDeletingTrip = false
            tripMutationError = "Could not delete this trip."
        }
    }
}
