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
            return "Supabase is not configured."
        case .notAuthenticated:
            return "No active Supabase session."
        case .unsupportedPayload:
            return "Payload is not valid for Supabase sync."
        case .invalidURL:
            return "Supabase URL is invalid."
        case .invalidResponse:
            return "Supabase response is invalid."
        case .emailConfirmationRequired:
            return "Account created. Confirm your email, then sign in."
        case .requestFailed(let statusCode, let body):
            if statusCode == 400 || statusCode == 401 {
                return "Authentication failed. Check email/password."
            }
            return "Supabase request failed (\(statusCode)). \(body)"
        }
    }
}
