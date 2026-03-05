import Foundation

struct SupabaseConfig {
    let projectURL: String
    let anonKey: String
    let tripsTable: String
    let feedbackTable: String
    let activitiesTable: String
    let profilesTable: String

    var isConfigured: Bool {
        !projectURL.isEmpty && !anonKey.isEmpty
    }

    static func load(bundle: Bundle = .main) -> SupabaseConfig {
        guard
            let url = bundle.url(forResource: "SupabaseConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else {
            return .placeholder
        }

        return SupabaseConfig(
            projectURL: raw["PROJECT_URL"] ?? "",
            anonKey: raw["ANON_KEY"] ?? "",
            tripsTable: raw["TRIPS_TABLE"] ?? "trips",
            feedbackTable: raw["FEEDBACK_TABLE"] ?? "traveler_feedback",
            activitiesTable: raw["ACTIVITIES_TABLE"] ?? "activities",
            profilesTable: raw["PROFILES_TABLE"] ?? "profiles"
        )
    }

    static let placeholder = SupabaseConfig(
        projectURL: "",
        anonKey: "",
        tripsTable: "trips",
        feedbackTable: "traveler_feedback",
        activitiesTable: "activities",
        profilesTable: "profiles"
    )
}
