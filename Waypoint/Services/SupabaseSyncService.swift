import Foundation

struct SupabaseSyncSnapshot {
    let profiles: [[String: String]]
    let trips: [[String: String]]
    let feedback: [[String: String]]
    let activities: [[String: String]]
}

struct SupabaseSyncService {
    let config: SupabaseConfig

    func push(
        operation: SyncOperation,
        accessToken: String,
        authenticatedUserID: String,
        session: URLSession = .shared
    ) async throws {
        guard config.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }
        guard !accessToken.isEmpty else {
            throw SupabaseServiceError.notAuthenticated
        }

        let request: URLRequest
        switch operation.type {
        case .deleteTrip:
            let payload = try decodePayload(from: operation)
            guard let tripId = payload["tripId"], !tripId.isEmpty else {
                throw SupabaseServiceError.unsupportedPayload
            }
            request = try makeDeleteRequest(
                tableName: config.tripsTable,
                filterColumn: "tripId",
                filterValue: tripId,
                accessToken: accessToken
            )
        case .deleteFeedback:
            let payload = try decodePayload(from: operation)
            guard let feedbackId = payload["feedbackId"], !feedbackId.isEmpty else {
                throw SupabaseServiceError.unsupportedPayload
            }
            request = try makeDeleteRequest(
                tableName: config.feedbackTable,
                filterColumn: "feedbackId",
                filterValue: feedbackId,
                accessToken: accessToken
            )
        case .deleteActivity:
            let payload = try decodePayload(from: operation)
            guard let activityId = payload["activityId"], !activityId.isEmpty else {
                throw SupabaseServiceError.unsupportedPayload
            }
            request = try makeDeleteRequest(
                tableName: config.activitiesTable,
                filterColumn: "activityId",
                filterValue: activityId,
                accessToken: accessToken
            )
        case .createTrip, .createFeedback, .updateFeedback, .saveActivities, .upsertProfile:
            var payload = try decodePayload(from: operation)
            if payload["authUserId"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                payload["authUserId"] = authenticatedUserID
            }
            let table = tableName(for: operation.type)
            let upsertConflict = conflictColumn(for: operation.type, payload: payload)
            request = try makeInsertOrUpsertRequest(
                tableName: table,
                payload: payload,
                accessToken: accessToken,
                onConflict: upsertConflict
            )
        }

        _ = try await send(request, session: session)
    }

    func fetchSnapshot(
        accessToken: String,
        authenticatedUserID: String,
        session: URLSession = .shared
    ) async throws -> SupabaseSyncSnapshot {
        let profiles = try await fetchRows(
            tableName: config.profilesTable,
            accessToken: accessToken,
            authenticatedUserID: authenticatedUserID,
            session: session
        )
        let trips = try await fetchRows(
            tableName: config.tripsTable,
            accessToken: accessToken,
            authenticatedUserID: authenticatedUserID,
            session: session
        )
        let feedback = try await fetchRows(
            tableName: config.feedbackTable,
            accessToken: accessToken,
            authenticatedUserID: authenticatedUserID,
            session: session
        )
        let activities = try await fetchRows(
            tableName: config.activitiesTable,
            accessToken: accessToken,
            authenticatedUserID: authenticatedUserID,
            session: session
        )
        return SupabaseSyncSnapshot(
            profiles: profiles,
            trips: trips,
            feedback: feedback,
            activities: activities
        )
    }

    private func tableName(for type: SyncOperationType) -> String {
        switch type {
        case .createTrip:
            return config.tripsTable
        case .createFeedback, .updateFeedback:
            return config.feedbackTable
        case .saveActivities:
            return config.activitiesTable
        case .upsertProfile:
            return config.profilesTable
        case .deleteTrip:
            return config.tripsTable
        case .deleteFeedback:
            return config.feedbackTable
        case .deleteActivity:
            return config.activitiesTable
        }
    }

    private func conflictColumn(for type: SyncOperationType, payload: [String: String]) -> String? {
        switch type {
        case .createTrip:
            return payload["tripId"] == nil ? nil : "tripId"
        case .createFeedback, .updateFeedback:
            return payload["feedbackId"] == nil ? nil : "feedbackId"
        case .saveActivities:
            return payload["activityId"] == nil ? nil : "activityId"
        case .upsertProfile:
            return "profileId"
        case .deleteTrip, .deleteFeedback, .deleteActivity:
            return nil
        }
    }

    private func decodePayload(from operation: SyncOperation) throws -> [String: String] {
        guard let payload = try? JSONDecoder().decode([String: String].self, from: Data(operation.payloadJSON.utf8)) else {
            throw SupabaseServiceError.unsupportedPayload
        }
        return payload
    }

    private func makeInsertOrUpsertRequest(
        tableName: String,
        payload: [String: String],
        accessToken: String,
        onConflict: String?
    ) throws -> URLRequest {
        guard
            let encodedTable = tableName.addingPercentEncoding(withAllowedCharacters: Self.pathComponentAllowed),
            var components = URLComponents(string: config.projectURL)
        else {
            throw SupabaseServiceError.invalidURL
        }

        components.path = "/rest/v1/\(encodedTable)"
        if let onConflict {
            components.queryItems = [URLQueryItem(name: "on_conflict", value: onConflict)]
        }

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if onConflict == nil {
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        } else {
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: [payload], options: [])
        return request
    }

    private func makeDeleteRequest(
        tableName: String,
        filterColumn: String,
        filterValue: String,
        accessToken: String
    ) throws -> URLRequest {
        guard
            let encodedTable = tableName.addingPercentEncoding(withAllowedCharacters: Self.pathComponentAllowed),
            var components = URLComponents(string: config.projectURL)
        else {
            throw SupabaseServiceError.invalidURL
        }

        components.path = "/rest/v1/\(encodedTable)"
        components.queryItems = [URLQueryItem(name: filterColumn, value: "eq.\(filterValue)")]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        return request
    }

    private func fetchRows(
        tableName: String,
        accessToken: String,
        authenticatedUserID: String,
        session: URLSession
    ) async throws -> [[String: String]] {
        guard !accessToken.isEmpty else {
            throw SupabaseServiceError.notAuthenticated
        }
        guard
            let encodedTable = tableName.addingPercentEncoding(withAllowedCharacters: Self.pathComponentAllowed),
            var components = URLComponents(string: config.projectURL)
        else {
            throw SupabaseServiceError.invalidURL
        }

        components.path = "/rest/v1/\(encodedTable)"
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "authUserId", value: "eq.\(authenticatedUserID)")
        ]

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await send(request, session: session)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        guard let rows = raw as? [[String: Any]] else {
            throw SupabaseServiceError.invalidResponse
        }
        return rows.map(Self.serializeRow)
    }

    private static func serializeRow(_ row: [String: Any]) -> [String: String] {
        var serialized: [String: String] = [:]
        for (key, value) in row {
            if value is NSNull {
                continue
            }
            serialized[key] = stringify(value)
        }
        return serialized
    }

    private static func stringify(_ value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any],
           let data = try? JSONSerialization.data(withJSONObject: array, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        if let dict = value as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return String(describing: value)
    }

    private func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SupabaseServiceError.requestFailed(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }

    private static let pathComponentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()
}
