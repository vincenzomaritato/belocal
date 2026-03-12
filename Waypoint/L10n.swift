import Foundation

enum L10n {
    private nonisolated static var preferredLanguageIdentifier: String {
        Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? Locale.current.identifier
    }

    nonisolated static func tr(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    nonisolated static func f(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: tr(key), locale: Locale.current, arguments: arguments)
    }

    nonisolated static func style(_ value: String) -> String {
        switch PlaceCanonicalizer.canonicalStyle(value) {
        case "Culture":
            return tr("Culture")
        case "Food":
            return tr("Food")
        case "Nature":
            return tr("Nature")
        case "Beach":
            return tr("Beach")
        case "Adventure":
            return tr("Adventure")
        case "Urban":
            return tr("Urban")
        case "Wellness":
            return tr("Wellness")
        case "Nightlife":
            return tr("Nightlife")
        case "Design":
            return tr("Design")
        case "Shopping":
            return tr("Shopping")
        case "Slow Travel":
            return tr("Slow Travel")
        default:
            return value
        }
    }

    nonisolated static func season(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "spring", "primavera":
            return tr("Spring")
        case "summer", "estate":
            return tr("Summer")
        case "autumn", "fall", "autunno":
            return tr("Autumn")
        case "winter", "inverno":
            return tr("Winter")
        default:
            return value
        }
    }

    nonisolated static func climate(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "warm":
            return tr("Warm")
        case "temperate":
            return tr("Temperate")
        case "cool":
            return tr("Cool")
        default:
            return value
        }
    }

    nonisolated static var preferredNarrativeLanguage: String {
        switch preferredLanguageCode {
        case "it":
            return "Italian"
        case "tr":
            return "Turkish"
        default:
            return "English"
        }
    }

    nonisolated static var preferredLanguageCode: String {
        preferredLanguageIdentifier
            .split(separator: "-")
            .first?
            .lowercased() ?? "en"
    }
}
