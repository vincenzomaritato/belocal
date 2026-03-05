import Foundation

struct TravelAPIConfig {
    let googlePlacesAPIKey: String
    let geoapifyAPIKey: String
    let openAIAPIKey: String
    let openAIModel: String
    let defaultOriginIATA: String

    var hasGooglePlaces: Bool { !googlePlacesAPIKey.isEmpty }
    var hasGeoapify: Bool { !geoapifyAPIKey.isEmpty }
    var hasOpenAI: Bool { !openAIAPIKey.isEmpty }

    static func load(bundle: Bundle = .main) -> TravelAPIConfig {
        let env = ProcessInfo.processInfo.environment

        guard
            let url = bundle.url(forResource: "TravelAPIConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let raw = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else {
            return TravelAPIConfig(
                googlePlacesAPIKey: env["GOOGLE_PLACES_API_KEY"] ?? env["GOOGLE_MAPS_API_KEY"] ?? "",
                geoapifyAPIKey: env["GEOAPIFY_API_KEY"] ?? "",
                openAIAPIKey: env["OPENAI_API_KEY"] ?? "",
                openAIModel: env["OPENAI_MODEL"] ?? placeholder.openAIModel,
                defaultOriginIATA: env["DEFAULT_ORIGIN_IATA"] ?? placeholder.defaultOriginIATA
            )
        }

        return TravelAPIConfig(
            googlePlacesAPIKey: env["GOOGLE_PLACES_API_KEY"] ?? env["GOOGLE_MAPS_API_KEY"] ?? raw["GOOGLE_PLACES_API_KEY"] ?? "",
            geoapifyAPIKey: env["GEOAPIFY_API_KEY"] ?? raw["GEOAPIFY_API_KEY"] ?? "",
            openAIAPIKey: env["OPENAI_API_KEY"] ?? raw["OPENAI_API_KEY"] ?? "",
            openAIModel: env["OPENAI_MODEL"] ?? raw["OPENAI_MODEL"] ?? placeholder.openAIModel,
            defaultOriginIATA: env["DEFAULT_ORIGIN_IATA"] ?? raw["DEFAULT_ORIGIN_IATA"] ?? placeholder.defaultOriginIATA
        )
    }

    static let placeholder = TravelAPIConfig(
        googlePlacesAPIKey: "",
        geoapifyAPIKey: "",
        openAIAPIKey: "",
        openAIModel: "gpt-5.1-mini",
        defaultOriginIATA: "FCO"
    )
}
