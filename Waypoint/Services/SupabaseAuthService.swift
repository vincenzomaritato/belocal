import Foundation

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String
    let email: String

    var isExpired: Bool {
        expiresAt <= .now
    }
}

enum SupabaseServiceError: Error {
    case notConfigured
    case notAuthenticated
    case unsupportedPayload
    case invalidURL
    case invalidResponse
    case emailConfirmationRequired
    case requestFailed(statusCode: Int, body: String)
}

struct SupabaseAuthService {
    let config: SupabaseConfig

    func signIn(email: String, password: String, session: URLSession = .shared) async throws -> SupabaseSession {
        guard config.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }

        let requestBody = [
            "email": email,
            "password": password
        ]

        let request = try makeAuthRequest(
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            body: requestBody
        )
        let data = try await send(request, session: session)
        let response = try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        return try makeSession(from: response)
    }

    func signUp(email: String, password: String, session: URLSession = .shared) async throws -> SupabaseSession {
        guard config.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }

        let requestBody = [
            "email": email,
            "password": password
        ]

        let request = try makeAuthRequest(path: "/auth/v1/signup", body: requestBody)
        let data = try await send(request, session: session)
        let response = try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        return try makeSession(from: response)
    }

    func refreshSession(refreshToken: String, session: URLSession = .shared) async throws -> SupabaseSession {
        guard config.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }
        guard !refreshToken.isEmpty else {
            throw SupabaseServiceError.notAuthenticated
        }

        let request = try makeAuthRequest(
            path: "/auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
            body: ["refresh_token": refreshToken]
        )
        let data = try await send(request, session: session)
        let response = try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        return try makeSession(from: response)
    }

    @MainActor
    func ensureValidAccessToken(settingsStore: AppSettingsStore, session: URLSession = .shared) async throws -> String {
        guard config.isConfigured else {
            throw SupabaseServiceError.notConfigured
        }
        guard settingsStore.isAuthenticated else {
            throw SupabaseServiceError.notAuthenticated
        }

        let nowPlusLeeway = Date().addingTimeInterval(60)
        if !settingsStore.supabaseAccessToken.isEmpty, settingsStore.supabaseTokenExpiresAt > nowPlusLeeway {
            return settingsStore.supabaseAccessToken
        }

        let refreshed = try await refreshSession(refreshToken: settingsStore.supabaseRefreshToken, session: session)
        settingsStore.updateSupabaseSession(refreshed)
        return refreshed.accessToken
    }

    private func makeSession(from response: SupabaseAuthResponse) throws -> SupabaseSession {
        guard
            let accessToken = response.accessToken,
            let refreshToken = response.refreshToken,
            let user = response.user,
            let email = user.email
        else {
            if response.user != nil {
                throw SupabaseServiceError.emailConfirmationRequired
            }
            throw SupabaseServiceError.invalidResponse
        }

        let expiryUnix: TimeInterval
        if let expiresAt = response.expiresAt {
            expiryUnix = expiresAt
        } else if let expiresIn = response.expiresIn {
            expiryUnix = Date().addingTimeInterval(TimeInterval(expiresIn)).timeIntervalSince1970
        } else {
            throw SupabaseServiceError.invalidResponse
        }

        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiryUnix),
            userID: user.id,
            email: email
        )
    }

    private func makeAuthRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: String]
    ) throws -> URLRequest {
        guard var components = URLComponents(string: config.projectURL) else {
            throw SupabaseServiceError.invalidURL
        }

        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw SupabaseServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)
        return request
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
}

private struct SupabaseAuthResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: TimeInterval?
    let user: SupabaseAuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

private struct SupabaseAuthUser: Decodable {
    let id: String
    let email: String?
}

extension SupabaseServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.tr("Supabase is not configured. Add a valid publishable key to SupabaseConfig.plist.")
        case .notAuthenticated:
            return L10n.tr("No active Supabase session.")
        case .unsupportedPayload:
            return L10n.tr("Payload is not valid for Supabase sync.")
        case .invalidURL:
            return L10n.tr("Supabase URL is invalid.")
        case .invalidResponse:
            return L10n.tr("Supabase response is invalid.")
        case .emailConfirmationRequired:
            return L10n.tr("Account created. Confirm your email, then sign in.")
        case .requestFailed(let statusCode, let body):
            if let friendlyMessage = Self.friendlyMessage(forStatusCode: statusCode, body: body) {
                return friendlyMessage
            }
            if let backendMessage = Self.backendMessage(from: body), !backendMessage.isEmpty {
                return L10n.f("Supabase request failed (%d). %@", statusCode, backendMessage)
            }
            return L10n.f("Supabase request failed (%d). %@", statusCode, body)
        }
    }

    private static func friendlyMessage(forStatusCode statusCode: Int, body: String) -> String? {
        let backendMessage = backendMessage(from: body)?.lowercased() ?? ""
        let normalizedBody = body.lowercased()
        let combined = "\(backendMessage) \(normalizedBody)"

        if combined.contains("user already registered") || combined.contains("user_already_exists") {
            return L10n.tr("An account with this email already exists. Sign in instead.")
        }

        if combined.contains("email not confirmed") || combined.contains("email_not_confirmed") {
            return L10n.tr("Confirm your email before signing in.")
        }

        if combined.contains("invalid api key") || combined.contains("invalid api_key") || combined.contains("publishable key") {
            return L10n.tr("Supabase is not configured. Add a valid publishable key to SupabaseConfig.plist.")
        }

        if statusCode == 400 || statusCode == 401 {
            return L10n.tr("Authentication failed. Check email/password.")
        }

        return nil
    }

    private static func backendMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8) else {
            return nil
        }

        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        for key in ["message", "error_description", "msg", "error", "code"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }

        return nil
    }
}
