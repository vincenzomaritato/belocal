import Foundation
import OSLog
import SwiftData

@MainActor
final class SyncManager {
    private struct ProtectedEntityIDs {
        var trips = Set<UUID>()
        var feedback = Set<UUID>()
        var activities = Set<UUID>()
    }

    private enum RetryDecision {
        case retry
        case stopRetrying
    }

    private let networkMonitor: NetworkMonitor
    private let settingsStore: AppSettingsStore
    private let supabaseSyncService: SupabaseSyncService
    private let supabaseAuthService: SupabaseAuthService
    private let logger = Logger(subsystem: "com.vmaritato.Waypoint", category: "SyncManager")
    private let maxRetryCount = 5
    private let downsyncIntervalSeconds: TimeInterval = 45
    private var lastDownsyncAt: Date = .distantPast

    init(
        networkMonitor: NetworkMonitor,
        settingsStore: AppSettingsStore,
        supabaseSyncService: SupabaseSyncService,
        supabaseAuthService: SupabaseAuthService
    ) {
        self.networkMonitor = networkMonitor
        self.settingsStore = settingsStore
        self.supabaseSyncService = supabaseSyncService
        self.supabaseAuthService = supabaseAuthService
    }

    func enqueue(type: SyncOperationType, payload: [String: String], context: ModelContext) {
        let payloadJSON = CodableStorage.encode(payload, fallback: "{}")
        context.insert(SyncOperation(type: type, payloadJSON: payloadJSON))
        _ = persist(context: context, stage: "enqueue")
    }

    func processPendingOperations(context: ModelContext, forceDownsync: Bool = false) async {
        guard networkMonitor.isOnline else {
            return
        }
        guard settingsStore.isAuthenticated else {
            return
        }
        guard supabaseSyncService.config.isConfigured else {
            resetNotConfiguredFailuresIfNeeded(context: context)
            return
        }

        let accessToken: String
        let authenticatedUserID = settingsStore.authenticatedUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !authenticatedUserID.isEmpty else {
            logger.error("Missing authenticated user id for Supabase sync.")
            return
        }
        do {
            accessToken = try await supabaseAuthService.ensureValidAccessToken(settingsStore: settingsStore)
        } catch {
            logger.error("Failed to ensure Supabase access token: \(error.localizedDescription, privacy: .public)")
            return
        }

        let descriptor = FetchDescriptor<SyncOperation>(sortBy: [SortDescriptor(\SyncOperation.createdAt)])
        let fetched: [SyncOperation]
        do {
            fetched = try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch sync operations: \(error.localizedDescription, privacy: .public)")
            return
        }

        let operations = fetched.filter {
            ($0.status == .pending || $0.status == .failed) && $0.retryCount < maxRetryCount
        }
        .sorted { lhs, rhs in
            let lhsPriority = operationPriority(lhs.type)
            let rhsPriority = operationPriority(rhs.type)
            if lhsPriority == rhsPriority {
                return lhs.createdAt < rhs.createdAt
            }
            return lhsPriority < rhsPriority
        }
        let processedAnyOperation = !operations.isEmpty
        var syncedOperations: [SyncOperation] = []

        for operation in operations {
            if operation.status == .failed, operation.retryCount > 0 {
                let backoffSeconds = min(30, 1 << min(operation.retryCount, 4))
                try? await Task.sleep(nanoseconds: UInt64(backoffSeconds) * 1_000_000_000)
            }

            operation.status = .syncing
            operation.lastError = nil
            guard persist(context: context, stage: "mark_syncing", operationID: operation.id) else {
                continue
            }

            do {
                try await supabaseSyncService.push(
                    operation: operation,
                    accessToken: accessToken,
                    authenticatedUserID: authenticatedUserID
                )
                operation.status = .synced
                operation.lastError = nil
                syncedOperations.append(operation)
            } catch {
                operation.status = .failed
                operation.lastError = error.localizedDescription
                switch retryDecision(for: error, currentRetryCount: operation.retryCount) {
                case .retry:
                    operation.retryCount += 1
                case .stopRetrying:
                    operation.retryCount = maxRetryCount
                }
            }

            _ = persist(context: context, stage: "finalize_operation", operationID: operation.id)
        }

        let shouldDownsyncAfterPush = processedAnyOperation
        let shouldRunDownsyncNow = shouldDownsyncAfterPush || forceDownsync || shouldRunDownsync()
        guard shouldRunDownsyncNow else { return }

        do {
            try await synchronizeFromSupabase(
                context: context,
                accessToken: accessToken,
                authenticatedUserID: authenticatedUserID
            )
            lastDownsyncAt = .now

            if !syncedOperations.isEmpty {
                syncedOperations.forEach(context.delete)
                _ = persist(context: context, stage: "cleanup_synced_operations")
            }
        } catch {
            logger.error("Supabase downsync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func shouldRunDownsync() -> Bool {
        Date().timeIntervalSince(lastDownsyncAt) >= downsyncIntervalSeconds
    }

    private func synchronizeFromSupabase(
        context: ModelContext,
        accessToken: String,
        authenticatedUserID: String
    ) async throws {
        let snapshot = try await supabaseSyncService.fetchSnapshot(
            accessToken: accessToken,
            authenticatedUserID: authenticatedUserID
        )
        let protectedIDs = try protectedEntityIDs(context: context)

        let destinationDescriptor = FetchDescriptor<Destination>()
        let localDestinations = try context.fetch(destinationDescriptor)
        var destinationsByID = Dictionary(uniqueKeysWithValues: localDestinations.map { ($0.id, $0) })

        var hasChanges = false
        hasChanges = try mergeProfiles(rows: snapshot.profiles, context: context) || hasChanges
        hasChanges = try mergeTrips(rows: snapshot.trips, context: context, destinationsByID: &destinationsByID) || hasChanges
        hasChanges = try mergeFeedback(rows: snapshot.feedback, context: context) || hasChanges
        hasChanges = try mergeActivities(rows: snapshot.activities, context: context) || hasChanges
        if !snapshot.trips.isEmpty || !snapshot.feedback.isEmpty || !snapshot.activities.isEmpty {
            hasChanges = try pruneRowsRemovedFromRemote(
                snapshot: snapshot,
                context: context,
                protectedIDs: protectedIDs
            ) || hasChanges
        }

        if hasChanges {
            _ = persist(context: context, stage: "downsync_merge")
        }
    }

    private func protectedEntityIDs(context: ModelContext) throws -> ProtectedEntityIDs {
        var protected = ProtectedEntityIDs()
        let descriptor = FetchDescriptor<SyncOperation>(sortBy: [SortDescriptor(\SyncOperation.createdAt)])
        let operations = try context.fetch(descriptor)

        for operation in operations where operation.status != .synced {
            guard
                let data = operation.payloadJSON.data(using: .utf8),
                let payload = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                continue
            }

            switch operation.type {
            case .createTrip:
                if let id = parseUUID(payload["tripId"]) {
                    protected.trips.insert(id)
                }
            case .createFeedback, .updateFeedback:
                if let id = parseUUID(payload["feedbackId"]) {
                    protected.feedback.insert(id)
                }
            case .saveActivities:
                if let id = parseUUID(payload["activityId"]) {
                    protected.activities.insert(id)
                }
            case .upsertProfile:
                break
            case .deleteTrip, .deleteFeedback, .deleteActivity:
                break
            }
        }

        return protected
    }

    private func pruneRowsRemovedFromRemote(
        snapshot: SupabaseSyncSnapshot,
        context: ModelContext,
        protectedIDs: ProtectedEntityIDs
    ) throws -> Bool {
        var changed = false

        let remoteTripIDs = Set(snapshot.trips.compactMap { parseUUID($0["tripId"]) })
        let remoteFeedbackIDs = Set(snapshot.feedback.compactMap { parseUUID($0["feedbackId"]) })
        let remoteActivityIDs = Set(snapshot.activities.compactMap { parseUUID($0["activityId"]) })

        let localTrips = try context.fetch(FetchDescriptor<Trip>())
        let localFeedback = try context.fetch(FetchDescriptor<TravelerFeedback>())
        let localActivities = try context.fetch(FetchDescriptor<ActivityItem>())

        var removedTripIDs = Set<UUID>()
        for trip in localTrips {
            guard !remoteTripIDs.contains(trip.id), !protectedIDs.trips.contains(trip.id) else {
                continue
            }
            removedTripIDs.insert(trip.id)
            context.delete(trip)
            changed = true
        }

        for item in localFeedback {
            let shouldRemoveByTrip = removedTripIDs.contains(item.tripId)
            let shouldRemoveByID = !remoteFeedbackIDs.contains(item.id) && !protectedIDs.feedback.contains(item.id)
            guard shouldRemoveByTrip || shouldRemoveByID else {
                continue
            }
            context.delete(item)
            changed = true
        }

        for item in localActivities {
            let shouldRemoveByTrip = removedTripIDs.contains(item.tripId)
            let shouldRemoveByID = !remoteActivityIDs.contains(item.id) && !protectedIDs.activities.contains(item.id)
            guard shouldRemoveByTrip || shouldRemoveByID else {
                continue
            }
            context.delete(item)
            changed = true
        }

        return changed
    }

    private func mergeProfiles(rows: [[String: String]], context: ModelContext) throws -> Bool {
        guard !rows.isEmpty else { return false }

        let descriptor = FetchDescriptor<UserProfile>()
        let localProfiles = try context.fetch(descriptor)
        var localByID = Dictionary(uniqueKeysWithValues: localProfiles.map { ($0.id, $0) })
        var localByAuthUserID = Dictionary(
            uniqueKeysWithValues: localProfiles.compactMap { profile in
                let authUserID = profile.authUserId.trimmingCharacters(in: .whitespacesAndNewlines)
                return authUserID.isEmpty ? nil : (authUserID, profile)
            }
        )

        var changed = false

        for row in rows {
            guard let profileID = parseUUID(row["profileId"]) else {
                continue
            }
            let authUserID = row["authUserId"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let preferredSeasons = parseList(row["preferredSeasons"])
            let styleWeights = CodableStorage.decode(
                row["travelStyleWeightsJSON"] ?? "{}",
                as: [String: Double].self,
                fallback: [:]
            )

            if let profile = localByID[profileID] ?? (!authUserID.isEmpty ? localByAuthUserID[authUserID] : nil) {
                profile.authUserId = authUserID
                profile.name = row["name"] ?? profile.name
                profile.budgetMin = parseDouble(row["budgetMin"], default: profile.budgetMin)
                profile.budgetMax = parseDouble(row["budgetMax"], default: profile.budgetMax)
                profile.ecoSensitivity = parseDouble(row["ecoSensitivity"], default: profile.ecoSensitivity)
                profile.peopleDefault = parseInt(row["peopleDefault"], default: profile.peopleDefault)
                profile.homeLatitude = parseDouble(row["homeLatitude"], default: profile.homeLatitude)
                profile.homeLongitude = parseDouble(row["homeLongitude"], default: profile.homeLongitude)
                profile.homeCity = row["homeCity"] ?? profile.homeCity
                profile.homeCountry = row["homeCountry"] ?? profile.homeCountry
                if !preferredSeasons.isEmpty {
                    profile.preferredSeasons = preferredSeasons
                }
                if !styleWeights.isEmpty {
                    profile.travelStyleWeights = styleWeights
                }
                changed = true
            } else {
                let profile = UserProfile(
                    id: profileID,
                    authUserId: authUserID,
                    name: row["name"] ?? "Traveler",
                    homeCity: row["homeCity"] ?? "",
                    homeCountry: row["homeCountry"] ?? "",
                    budgetMin: parseDouble(row["budgetMin"], default: 1000),
                    budgetMax: parseDouble(row["budgetMax"], default: 3000),
                    preferredSeasons: preferredSeasons.isEmpty ? ["Spring", "Autumn"] : preferredSeasons,
                    travelStyleWeights: styleWeights.isEmpty ? ["Culture": 0.25, "Food": 0.25, "Nature": 0.25, "Beach": 0.25] : styleWeights,
                    ecoSensitivity: parseDouble(row["ecoSensitivity"], default: 0.6),
                    peopleDefault: parseInt(row["peopleDefault"], default: 2),
                    homeLatitude: parseDouble(row["homeLatitude"], default: TravelDistanceCalculator.defaultHomeLatitude),
                    homeLongitude: parseDouble(row["homeLongitude"], default: TravelDistanceCalculator.defaultHomeLongitude)
                )
                context.insert(profile)
                localByID[profileID] = profile
                if !authUserID.isEmpty {
                    localByAuthUserID[authUserID] = profile
                }
                changed = true
            }
        }

        return changed
    }

    private func mergeTrips(
        rows: [[String: String]],
        context: ModelContext,
        destinationsByID: inout [UUID: Destination]
    ) throws -> Bool {
        guard !rows.isEmpty else { return false }

        let tripDescriptor = FetchDescriptor<Trip>()
        let localTrips = try context.fetch(tripDescriptor)
        var localByID = Dictionary(uniqueKeysWithValues: localTrips.map { ($0.id, $0) })

        let profileDescriptor = FetchDescriptor<UserProfile>()
        let fallbackUserID = try context.fetch(profileDescriptor).first?.id

        var changed = false

        for row in rows {
            guard let tripID = parseUUID(row["tripId"]) else {
                continue
            }
            guard let destinationID = parseUUID(row["destinationId"]) else {
                continue
            }

            let userID = parseUUID(row["userId"]) ?? fallbackUserID
            guard let userID else {
                continue
            }

            let destination = resolveDestination(
                destinationID: destinationID,
                row: row,
                context: context,
                destinationsByID: &destinationsByID
            )

            let startDate = parseDate(row["startDate"]) ?? .now
            let endDate = parseDate(row["endDate"]) ?? startDate
            let transport = TransportType(rawValue: row["transportType"] ?? "") ?? .plane
            let tripIntent = TripIntent(rawValue: row["intent"] ?? "") ?? TripIntent.inferred(startDate: startDate, endDate: endDate)
            let people = parseInt(row["people"], default: 1)
            let budgetSpent = parseDouble(row["budgetSpent"], default: 0)
            let co2Estimated = parseDouble(row["co2Estimated"], default: 0)
            let ecoScoreSnapshot = parseDouble(row["ecoScoreSnapshot"], default: destination.ecoScore)

            if let trip = localByID[tripID] {
                trip.userId = userID
                trip.destinationId = destination.id
                trip.startDate = startDate
                trip.endDate = max(endDate, startDate)
                trip.transportType = transport
                trip.tripIntent = tripIntent
                trip.people = max(1, people)
                trip.budgetSpent = max(0, budgetSpent)
                trip.co2Estimated = max(0, co2Estimated)
                trip.ecoScoreSnapshot = ecoScoreSnapshot
                changed = true
            } else {
                let trip = Trip(
                    id: tripID,
                    userId: userID,
                    destinationId: destination.id,
                    startDate: startDate,
                    endDate: max(endDate, startDate),
                    transportType: transport,
                    tripIntent: tripIntent,
                    people: max(1, people),
                    budgetSpent: max(0, budgetSpent),
                    co2Estimated: max(0, co2Estimated),
                    ecoScoreSnapshot: ecoScoreSnapshot
                )
                context.insert(trip)
                localByID[tripID] = trip
                changed = true
            }
        }

        return changed
    }

    private func mergeFeedback(rows: [[String: String]], context: ModelContext) throws -> Bool {
        guard !rows.isEmpty else { return false }

        let descriptor = FetchDescriptor<TravelerFeedback>()
        let localItems = try context.fetch(descriptor)
        var localByID = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0) })

        var changed = false

        for row in rows {
            guard let feedbackID = parseUUID(row["feedbackId"]) else {
                continue
            }
            let tripID = parseUUID(row["tripId"]) ?? feedbackID

            let destinationID = parseUUID(row["destinationId"])
            let destinationName = row["destinationName"] ?? ""
            let destinationCountry = row["destinationCountry"] ?? ""
            let rating = parseInt(row["rating"], default: 3)
            let tags = parseList(row["tags"])
            let text = row["text"] ?? ""
            let crowding = parseDouble(row["crowding"], default: 0.5)
            let value = parseDouble(row["value"], default: 0.5)
            let sustainability = parseDouble(row["sustainabilityPerception"], default: 0.5)
            let sourceType = FeedbackSourceType(rawValue: row["sourceType"] ?? "") ?? .traveler
            let createdAt = parseDate(row["createdAt"]) ?? .now

            if let item = localByID[feedbackID] {
                item.tripId = tripID
                item.destinationId = destinationID
                item.destinationName = destinationName
                item.destinationCountry = destinationCountry
                item.rating = rating
                item.tags = tags
                item.text = text
                item.crowding = crowding
                item.value = value
                item.sustainabilityPerception = sustainability
                item.sourceType = sourceType
                item.authorHomeCity = row["authorHomeCity"]
                item.authorHomeCountry = row["authorHomeCountry"]
                item.sentiment = row["sentiment"]
                item.createdAt = createdAt
                changed = true
            } else {
                let item = TravelerFeedback(
                    id: feedbackID,
                    tripId: tripID,
                    destinationId: destinationID,
                    destinationName: destinationName,
                    destinationCountry: destinationCountry,
                    rating: rating,
                    tags: tags,
                    text: text,
                    crowding: crowding,
                    value: value,
                    sustainabilityPerception: sustainability,
                    sourceType: sourceType,
                    authorHomeCity: row["authorHomeCity"],
                    authorHomeCountry: row["authorHomeCountry"],
                    sentiment: row["sentiment"],
                    createdAt: createdAt
                )
                context.insert(item)
                localByID[feedbackID] = item
                changed = true
            }
        }

        return changed
    }

    private func mergeActivities(rows: [[String: String]], context: ModelContext) throws -> Bool {
        guard !rows.isEmpty else { return false }

        let descriptor = FetchDescriptor<ActivityItem>()
        let localItems = try context.fetch(descriptor)
        var localByID = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0) })

        var changed = false

        for row in rows {
            guard let activityID = parseUUID(row["activityId"]),
                  let tripID = parseUUID(row["tripId"]) else {
                continue
            }

            let type = ActivityType(rawValue: row["type"] ?? "") ?? .activity
            let title = row["title"] ?? ""
            let note = row["note"] ?? ""
            let metaJSON = row["metaJSON"]
            let externalID = row["externalId"]

            if let item = localByID[activityID] {
                item.tripId = tripID
                item.type = type
                item.title = title
                item.note = note
                item.metaJSON = metaJSON
                item.externalId = externalID
                changed = true
            } else {
                let item = ActivityItem(
                    id: activityID,
                    tripId: tripID,
                    type: type,
                    title: title,
                    note: note,
                    externalId: externalID,
                    metaJSON: metaJSON
                )
                context.insert(item)
                localByID[activityID] = item
                changed = true
            }
        }

        return changed
    }

    private func resolveDestination(
        destinationID: UUID,
        row: [String: String],
        context: ModelContext,
        destinationsByID: inout [UUID: Destination]
    ) -> Destination {
        if let existing = destinationsByID[destinationID] {
            return existing
        }

        let styles = parseList(row["destinationStylesJSON"])
        let typicalSeason = parseList(row["destinationTypicalSeasonJSON"])

        let created = Destination(
            id: destinationID,
            name: row["destinationName"] ?? L10n.tr("Unknown destination"),
            country: row["destinationCountry"] ?? "Unknown",
            latitude: parseDouble(row["destinationLatitude"], default: 0),
            longitude: parseDouble(row["destinationLongitude"], default: 0),
            styles: styles,
            climate: row["destinationClimate"] ?? "Temperate",
            costIndex: parseDouble(row["destinationCostIndex"], default: 0.5),
            ecoScore: parseDouble(row["destinationEcoScore"], default: 50),
            crowdingIndex: parseDouble(row["destinationCrowdingIndex"], default: 0.5),
            typicalSeason: typicalSeason,
            distanceKm: parseDouble(row["destinationDistanceKm"], default: 0)
        )

        context.insert(created)
        destinationsByID[destinationID] = created
        return created
    }

    private func parseUUID(_ raw: String?) -> UUID? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private func parseInt(_ raw: String?, default defaultValue: Int) -> Int {
        guard let raw else { return defaultValue }
        if let parsed = Int(raw) {
            return parsed
        }
        if let parsed = Double(raw) {
            return Int(parsed.rounded())
        }
        return defaultValue
    }

    private func parseDouble(_ raw: String?, default defaultValue: Double) -> Double {
        guard let raw, let parsed = Double(raw) else {
            return defaultValue
        }
        return parsed
    }

    private func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        if let date = Self.iso8601Fractional.date(from: raw) {
            return date
        }
        if let date = Self.iso8601.date(from: raw) {
            return date
        }
        if let timestamp = Double(raw) {
            return Date(timeIntervalSince1970: timestamp)
        }
        return nil
    }

    private func parseList(_ raw: String?) -> [String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") {
            let values = CodableStorage.decode(trimmed, as: [String].self, fallback: [])
            return values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return trimmed
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func resetNotConfiguredFailuresIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<SyncOperation>(sortBy: [SortDescriptor(\SyncOperation.createdAt)])
        guard let operations = try? context.fetch(descriptor) else { return }

        var didChange = false
        for operation in operations where operation.status == .failed {
            let errorText = operation.lastError?.lowercased() ?? ""
            guard errorText.contains("not configured") || errorText.contains("supabase is not configured") else {
                continue
            }

            operation.status = .pending
            operation.retryCount = 0
            operation.lastError = nil
            didChange = true
        }

        if didChange {
            _ = persist(context: context, stage: "reset_not_configured_failures")
        }
    }

    private func retryDecision(
        for error: Error,
        currentRetryCount: Int
    ) -> RetryDecision {
        guard currentRetryCount + 1 < maxRetryCount else {
            return .stopRetrying
        }

        guard let supabaseError = error as? SupabaseServiceError else {
            return .retry
        }

        switch supabaseError {
        case .notConfigured, .unsupportedPayload, .invalidURL, .notAuthenticated, .emailConfirmationRequired:
            return .stopRetrying
        case .requestFailed(let statusCode, _):
            if (400..<500).contains(statusCode), statusCode != 408, statusCode != 429 {
                return .stopRetrying
            }
            return .retry
        case .invalidResponse:
            return .retry
        }
    }

    private func operationPriority(_ type: SyncOperationType) -> Int {
        switch type {
        case .upsertProfile:
            return 0
        case .createTrip, .createFeedback, .updateFeedback, .saveActivities, .deleteTrip, .deleteFeedback, .deleteActivity:
            return 1
        }
    }

    @discardableResult
    private func persist(
        context: ModelContext,
        stage: String,
        operationID: UUID? = nil
    ) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            let operationHint = operationID?.uuidString ?? "n/a"
            logger.error("Failed to save sync context at stage=\(stage, privacy: .public), operation=\(operationHint, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
