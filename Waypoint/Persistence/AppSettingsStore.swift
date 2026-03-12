import Foundation
import Observation

@Observable
@MainActor
final class AppSettingsStore {
    private let defaults: UserDefaults
    private let tokenStore: KeychainTokenStore

    var isAuthenticated: Bool {
        didSet {
            defaults.set(isAuthenticated, forKey: Keys.isAuthenticated)
        }
    }

    var authenticatedEmail: String {
        didSet {
            defaults.set(authenticatedEmail, forKey: Keys.authenticatedEmail)
        }
    }

    var authenticatedUserID: String {
        didSet {
            defaults.set(authenticatedUserID, forKey: Keys.authenticatedUserID)
        }
    }

    var supabaseAccessToken: String {
        didSet {
            tokenStore.set(supabaseAccessToken, for: .supabaseAccessToken)
        }
    }

    var supabaseRefreshToken: String {
        didSet {
            tokenStore.set(supabaseRefreshToken, for: .supabaseRefreshToken)
        }
    }

    var supabaseTokenExpiresAt: Date {
        didSet {
            defaults.set(supabaseTokenExpiresAt, forKey: Keys.supabaseTokenExpiresAt)
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    var hasSeenOnboardingWelcome: Bool {
        didSet {
            defaults.set(hasSeenOnboardingWelcome, forKey: Keys.hasSeenOnboardingWelcome)
        }
    }

    init(defaults: UserDefaults = .standard, tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.isAuthenticated = defaults.bool(forKey: Keys.isAuthenticated)
        self.authenticatedEmail = defaults.string(forKey: Keys.authenticatedEmail) ?? ""
        self.authenticatedUserID = defaults.string(forKey: Keys.authenticatedUserID) ?? ""
        let legacyAccessToken = defaults.string(forKey: Keys.supabaseAccessToken) ?? ""
        let storedAccessToken = tokenStore.string(for: .supabaseAccessToken)
        self.supabaseAccessToken = storedAccessToken.isEmpty ? legacyAccessToken : storedAccessToken
        let legacyRefreshToken = defaults.string(forKey: Keys.supabaseRefreshToken) ?? ""
        let storedRefreshToken = tokenStore.string(for: .supabaseRefreshToken)
        self.supabaseRefreshToken = storedRefreshToken.isEmpty ? legacyRefreshToken : storedRefreshToken
        self.supabaseTokenExpiresAt = defaults.object(forKey: Keys.supabaseTokenExpiresAt) as? Date ?? .distantPast
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.hasSeenOnboardingWelcome = defaults.bool(forKey: Keys.hasSeenOnboardingWelcome)

        migrateLegacyTokensIfNeeded(
            legacyAccessToken: legacyAccessToken,
            legacyRefreshToken: legacyRefreshToken
        )
    }

    func completeSignIn(email: String) {
        authenticatedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        authenticatedUserID = ""
        supabaseAccessToken = ""
        supabaseRefreshToken = ""
        supabaseTokenExpiresAt = .distantPast
        isAuthenticated = true
        hasCompletedOnboarding = true
        hasSeenOnboardingWelcome = true
    }

    func completeRegistration(email: String) {
        authenticatedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        authenticatedUserID = ""
        supabaseAccessToken = ""
        supabaseRefreshToken = ""
        supabaseTokenExpiresAt = .distantPast
        isAuthenticated = true
        hasCompletedOnboarding = false
        hasSeenOnboardingWelcome = false
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        hasSeenOnboardingWelcome = false
    }

    func completeSupabaseSignIn(session: SupabaseSession, rememberEmail: Bool) {
        authenticatedEmail = rememberEmail ? session.email : ""
        authenticatedUserID = session.userID
        supabaseAccessToken = session.accessToken
        supabaseRefreshToken = session.refreshToken
        supabaseTokenExpiresAt = session.expiresAt
        isAuthenticated = true
        hasCompletedOnboarding = true
        hasSeenOnboardingWelcome = true
    }

    func completeSupabaseRegistration(session: SupabaseSession, rememberEmail: Bool) {
        authenticatedEmail = rememberEmail ? session.email : ""
        authenticatedUserID = session.userID
        supabaseAccessToken = session.accessToken
        supabaseRefreshToken = session.refreshToken
        supabaseTokenExpiresAt = session.expiresAt
        isAuthenticated = true
        hasCompletedOnboarding = false
        hasSeenOnboardingWelcome = false
    }

    func updateSupabaseSession(_ session: SupabaseSession) {
        supabaseAccessToken = session.accessToken
        supabaseRefreshToken = session.refreshToken
        supabaseTokenExpiresAt = session.expiresAt
        if authenticatedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            authenticatedEmail = session.email
        }
        if authenticatedUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            authenticatedUserID = session.userID
        }
    }

    func markOnboardingWelcomeSeen() {
        hasSeenOnboardingWelcome = true
    }

    func rememberAuthEmail(_ email: String?) {
        authenticatedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func signOut() {
        isAuthenticated = false
        authenticatedEmail = ""
        authenticatedUserID = ""
        supabaseAccessToken = ""
        supabaseRefreshToken = ""
        supabaseTokenExpiresAt = .distantPast
        hasCompletedOnboarding = false
        hasSeenOnboardingWelcome = false
    }

    private enum Keys {
        static let isAuthenticated = "settings.auth.isAuthenticated"
        static let authenticatedEmail = "settings.auth.email"
        static let authenticatedUserID = "settings.auth.userID"
        static let supabaseAccessToken = "settings.auth.supabase.accessToken"
        static let supabaseRefreshToken = "settings.auth.supabase.refreshToken"
        static let supabaseTokenExpiresAt = "settings.auth.supabase.expiresAt"
        static let hasCompletedOnboarding = "settings.auth.hasCompletedOnboarding"
        static let hasSeenOnboardingWelcome = "settings.auth.hasSeenOnboardingWelcome"
    }

    private func migrateLegacyTokensIfNeeded(
        legacyAccessToken: String,
        legacyRefreshToken: String
    ) {
        if !legacyAccessToken.isEmpty && tokenStore.string(for: .supabaseAccessToken).isEmpty {
            tokenStore.set(legacyAccessToken, for: .supabaseAccessToken)
        }
        if !legacyRefreshToken.isEmpty && tokenStore.string(for: .supabaseRefreshToken).isEmpty {
            tokenStore.set(legacyRefreshToken, for: .supabaseRefreshToken)
        }

        defaults.removeObject(forKey: Keys.supabaseAccessToken)
        defaults.removeObject(forKey: Keys.supabaseRefreshToken)
    }
}
