import Foundation

struct SupabaseConfig {
    let projectURL: String
    let anonKey: String
    let tripsTable: String
    let feedbackTable: String
    let activitiesTable: String
    let profilesTable: String

    var isConfigured: Bool {
        let normalizedProjectURL = projectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAnonKey = anonKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedProjectURL.isEmpty, !normalizedAnonKey.isEmpty else {
            return false
        }

        let placeholderValues = [
            "YOUR_SUPABASE_PUBLISHABLE_KEY",
            "YOUR_SUPABASE_ANON_KEY",
            "YOUR_SUPABASE_PROJECT_URL"
        ]

        return !placeholderValues.contains(where: { $0.caseInsensitiveCompare(normalizedAnonKey) == .orderedSame })
            && !placeholderValues.contains(where: { $0.caseInsensitiveCompare(normalizedProjectURL) == .orderedSame })
    }

    static func load(bundle: Bundle = .main) -> SupabaseConfig {
        let env = ProcessInfo.processInfo.environment

        guard
            let url = bundle.url(forResource: "SupabaseConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else {
            return .placeholder
        }

        return SupabaseConfig(
            projectURL: env["SUPABASE_PROJECT_URL"] ?? env["SUPABASE_URL"] ?? raw["PROJECT_URL"] ?? "",
            anonKey: env["SUPABASE_PUBLISHABLE_KEY"] ?? env["SUPABASE_ANON_KEY"] ?? raw["ANON_KEY"] ?? "",
            tripsTable: env["SUPABASE_TRIPS_TABLE"] ?? raw["TRIPS_TABLE"] ?? "trips",
            feedbackTable: env["SUPABASE_FEEDBACK_TABLE"] ?? raw["FEEDBACK_TABLE"] ?? "traveler_feedback",
            activitiesTable: env["SUPABASE_ACTIVITIES_TABLE"] ?? raw["ACTIVITIES_TABLE"] ?? "activities",
            profilesTable: env["SUPABASE_PROFILES_TABLE"] ?? raw["PROFILES_TABLE"] ?? "profiles"
        )
    }

    static let placeholder = SupabaseConfig(
        projectURL: "YOUR_SUPABASE_PROJECT_URL",
        anonKey: "YOUR_SUPABASE_PUBLISHABLE_KEY",
        tripsTable: "trips",
        feedbackTable: "traveler_feedback",
        activitiesTable: "activities",
        profilesTable: "profiles"
    )
}
