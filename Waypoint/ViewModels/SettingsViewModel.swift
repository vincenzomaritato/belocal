import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftData

@MainActor
@Observable
final class SettingsViewModel {
    enum BudgetPreset: String, CaseIterable, Identifiable {
        case essential
        case comfort
        case premium
        case luxury

        var id: String { rawValue }

        var title: String {
            switch self {
            case .essential: return L10n.tr("Essential")
            case .comfort: return L10n.tr("Comfort")
            case .premium: return L10n.tr("Premium")
            case .luxury: return L10n.tr("Luxury")
            }
        }

        var range: ClosedRange<Double> {
            switch self {
            case .essential: return 500...1800
            case .comfort: return 1200...3200
            case .premium: return 2500...6200
            case .luxury: return 5000...12000
            }
        }

        var subtitle: String {
            "€\(Int(range.lowerBound)) - €\(Int(range.upperBound))"
        }
    }

    enum EcoPreset: String, CaseIterable, Identifiable {
        case low
        case balanced
        case high

        var id: String { rawValue }

        var title: String {
            switch self {
            case .low: return L10n.tr("Low")
            case .balanced: return L10n.tr("Balanced")
            case .high: return L10n.tr("High")
            }
        }

        var value: Double {
            switch self {
            case .low: return 0.30
            case .balanced: return 0.60
            case .high: return 0.85
            }
        }
    }

    enum StylePreset: String, CaseIterable, Identifiable {
        case balanced
        case culture
        case food
        case nature
        case beach

        var id: String { rawValue }

        var title: String {
            switch self {
            case .balanced: return L10n.tr("Balanced")
            case .culture: return L10n.tr("Culture")
            case .food: return L10n.tr("Food")
            case .nature: return L10n.tr("Nature")
            case .beach: return L10n.tr("Beach")
            }
        }

        var weights: [String: Double] {
            switch self {
            case .balanced:
                return ["Culture": 0.25, "Food": 0.25, "Nature": 0.25, "Beach": 0.25]
            case .culture:
                return ["Culture": 0.55, "Food": 0.15, "Nature": 0.15, "Beach": 0.15]
            case .food:
                return ["Culture": 0.15, "Food": 0.55, "Nature": 0.15, "Beach": 0.15]
            case .nature:
                return ["Culture": 0.15, "Food": 0.15, "Nature": 0.55, "Beach": 0.15]
            case .beach:
                return ["Culture": 0.15, "Food": 0.15, "Nature": 0.15, "Beach": 0.55]
            }
        }
    }

    var profileName = ""
    var budgetMin: Double = 1000
    var budgetMax: Double = 3000
    var ecoSensitivity: Double = 0.7
    var peopleDefault: Int = 2
    var homeCity: String = ""
    var homeCountry: String = ""
    var homeLatitude: Double = TravelDistanceCalculator.defaultHomeLatitude
    var homeLongitude: Double = TravelDistanceCalculator.defaultHomeLongitude
    var preferredSeasons: Set<String> = ["Spring", "Autumn"]
    var styleWeights: [String: Double] = [
        "Culture": 0.3,
        "Food": 0.25,
        "Nature": 0.25,
        "Beach": 0.2
    ]
    var homeLocationLabel = SettingsViewModel.unsetLabel

    var saveMessage: String?
    var saveMessageIsError = false

    static let seasonOrder = ["Spring", "Summer", "Autumn", "Winter"]
    static let defaultProfileName = "Traveler"

    static var unsetLabel: String {
        L10n.tr("Not set")
    }

    static func seasonTitle(for season: String) -> String {
        switch season {
        case "Spring": return L10n.tr("Spring")
        case "Summer": return L10n.tr("Summer")
        case "Autumn": return L10n.tr("Autumn")
        case "Winter": return L10n.tr("Winter")
        default: return season
        }
    }

    static func styleCategoryTitle(for key: String) -> String {
        switch key {
        case "Culture": return L10n.tr("Culture")
        case "Food": return L10n.tr("Food")
        case "Nature": return L10n.tr("Nature")
        case "Beach": return L10n.tr("Beach")
        default: return key
        }
    }

    func load(from profile: UserProfile?) {
        guard let profile else { return }
        profileName = profile.name
        budgetMin = profile.budgetMin
        budgetMax = profile.budgetMax
        ecoSensitivity = profile.ecoSensitivity
        peopleDefault = profile.peopleDefault
        homeCity = profile.homeCity
        homeCountry = profile.homeCountry
        homeLatitude = profile.homeLatitude
        homeLongitude = profile.homeLongitude
        preferredSeasons = Set(profile.preferredSeasons)
        styleWeights = profile.travelStyleWeights
        homeLocationLabel = profile.homeLocationLabel

        Task {
            await refreshHomeLocationLabel()
        }
    }

    func save(to profile: UserProfile?, context: ModelContext, homeViewModel: HomeViewModel, bootstrap: AppBootstrap) {
        guard let profile else { return }

        applyDraft(to: profile)

        do {
            try context.save()

            if bootstrap.supabaseSyncService.config.isConfigured {
                bootstrap.syncManager.enqueue(
                    type: .upsertProfile,
                    payload: profileSyncPayload(
                        for: profile,
                        authUserID: bootstrap.settingsStore.authenticatedUserID
                    ),
                    context: context
                )
                saveMessage = L10n.tr("Profile saved. Supabase sync is in queue.")
            } else {
                saveMessage = L10n.tr("Profile saved locally. Supabase sync is not configured.")
            }
            saveMessageIsError = false

            homeViewModel.load(context: context, bootstrap: bootstrap)
        } catch {
            saveMessage = L10n.tr("Could not save profile changes. Try again.")
            saveMessageIsError = true
        }
    }

    func applyDraft(to profile: UserProfile?) {
        guard let profile else { return }
        profile.name = profileName.isEmpty ? Self.defaultProfileName : profileName
        profile.budgetMin = min(budgetMin, budgetMax)
        profile.budgetMax = max(budgetMin, budgetMax)
        profile.ecoSensitivity = ecoSensitivity
        profile.peopleDefault = peopleDefault
        profile.homeCity = homeCity.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.homeCountry = homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.homeLatitude = clamp(homeLatitude, min: -90, max: 90)
        profile.homeLongitude = clamp(homeLongitude, min: -180, max: 180)
        profile.preferredSeasons = Array(preferredSeasons)
        profile.travelStyleWeights = normalized(weights: styleWeights)
    }

    func resetState() {
        profileName = ""
        budgetMin = 1000
        budgetMax = 3000
        ecoSensitivity = 0.7
        peopleDefault = 2
        homeCity = ""
        homeCountry = ""
        homeLatitude = TravelDistanceCalculator.defaultHomeLatitude
        homeLongitude = TravelDistanceCalculator.defaultHomeLongitude
        preferredSeasons = ["Spring", "Autumn"]
        styleWeights = [
            "Culture": 0.3,
            "Food": 0.25,
            "Nature": 0.25,
            "Beach": 0.2
        ]
        homeLocationLabel = Self.unsetLabel
        saveMessage = nil
        saveMessageIsError = false
    }

    private func normalized(weights: [String: Double]) -> [String: Double] {
        let sum = weights.values.reduce(0, +)
        guard sum > 0 else { return weights }
        return Dictionary(uniqueKeysWithValues: weights.map { ($0.key, $0.value / sum) })
    }

    private func clamp(_ value: Double, min lower: Double, max upper: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }

    private func profileSyncPayload(for profile: UserProfile, authUserID: String) -> [String: String] {
        let normalizedAuthUserID = authUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "profileId": profile.id.uuidString,
            "authUserId": normalizedAuthUserID,
            "name": profile.name,
            "budgetMin": String(format: "%.0f", profile.budgetMin),
            "budgetMax": String(format: "%.0f", profile.budgetMax),
            "ecoSensitivity": String(format: "%.3f", profile.ecoSensitivity),
            "peopleDefault": "\(profile.peopleDefault)",
            "homeLatitude": String(format: "%.6f", profile.homeLatitude),
            "homeLongitude": String(format: "%.6f", profile.homeLongitude),
            "homeCity": profile.homeCity,
            "homeCountry": profile.homeCountry,
            "preferredSeasons": profile.preferredSeasons.sorted().joined(separator: ","),
            "travelStyleWeightsJSON": profile.travelStyleWeightsJSON,
            "updatedAt": ISO8601DateFormatter().string(from: .now)
        ]
    }

    func setHomeLocation(latitude: Double, longitude: Double, city: String, country: String, label: String) {
        homeLatitude = clamp(latitude, min: -90, max: 90)
        homeLongitude = clamp(longitude, min: -180, max: 180)
        let trimmedCity = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCountry = country.trimmingCharacters(in: .whitespacesAndNewlines)
        homeCity = trimmedCity
        homeCountry = trimmedCountry
        let fallbackLabel = [trimmedCity, trimmedCountry].filter { !$0.isEmpty }.joined(separator: ", ")
        homeLocationLabel = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (fallbackLabel.isEmpty ? Self.unsetLabel : fallbackLabel)
            : label
    }

    func refreshHomeLocationLabel() async {
        let location = CLLocation(latitude: homeLatitude, longitude: homeLongitude)
        if #available(iOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else {
                let fallback = [homeCity, homeCountry].filter { !$0.isEmpty }.joined(separator: ", ")
                homeLocationLabel = fallback.isEmpty ? Self.unsetLabel : fallback
                return
            }

            do {
                let mapItems = try await request.mapItems
                if let item = mapItems.first {
                    let city = item.addressRepresentations?.cityName ?? item.name ?? ""
                    let country = item.addressRepresentations?.regionName ?? ""
                    if !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        homeCity = city
                    }
                    if !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        homeCountry = country
                    }
                    let composed = [city, country]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .joined(separator: ", ")
                    let fallback = [homeCity, homeCountry].filter { !$0.isEmpty }.joined(separator: ", ")
                    homeLocationLabel = composed.isEmpty ? (fallback.isEmpty ? Self.unsetLabel : fallback) : composed
                    return
                }
            } catch {
                // Keep fallback label when reverse geocoding is unavailable.
            }
        } else {
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    let city = placemark.locality ?? placemark.subAdministrativeArea ?? ""
                    let country = placemark.country ?? ""
                    if !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        homeCity = city
                    }
                    if !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        homeCountry = country
                    }
                    let composed = [city, country].filter { !$0.isEmpty }.joined(separator: ", ")
                    let fallback = [homeCity, homeCountry].filter { !$0.isEmpty }.joined(separator: ", ")
                    homeLocationLabel = composed.isEmpty ? (fallback.isEmpty ? Self.unsetLabel : fallback) : composed
                    return
                }
            } catch {
                // Keep fallback label when reverse geocoding is unavailable.
            }
        }

        let fallback = [homeCity, homeCountry].filter { !$0.isEmpty }.joined(separator: ", ")
        homeLocationLabel = fallback.isEmpty ? Self.unsetLabel : fallback
    }

    var selectedBudgetPreset: BudgetPreset {
        get {
            let targetMin = budgetMin
            let targetMax = budgetMax
            return BudgetPreset.allCases.min { lhs, rhs in
                let lhsScore = abs(lhs.range.lowerBound - targetMin) + abs(lhs.range.upperBound - targetMax)
                let rhsScore = abs(rhs.range.lowerBound - targetMin) + abs(rhs.range.upperBound - targetMax)
                return lhsScore < rhsScore
            } ?? .comfort
        }
        set {
            budgetMin = newValue.range.lowerBound
            budgetMax = newValue.range.upperBound
        }
    }

    var selectedEcoPreset: EcoPreset {
        get {
            EcoPreset.allCases.min { abs($0.value - ecoSensitivity) < abs($1.value - ecoSensitivity) } ?? .balanced
        }
        set {
            ecoSensitivity = newValue.value
        }
    }

    var selectedStylePreset: StylePreset {
        get {
            let normalizedWeights = normalized(weights: styleWeights)
            let trackedKeys = ["Culture", "Food", "Nature", "Beach"]
            let trackedValues = trackedKeys.map { normalizedWeights[$0] ?? 0 }

            if trackedValues.allSatisfy({ $0 == 0 }) {
                return .balanced
            }

            let average = trackedValues.reduce(0, +) / Double(trackedValues.count)
            let maxDeviation = trackedValues.map { abs($0 - average) }.max() ?? 0
            if maxDeviation <= 0.06 {
                return .balanced
            }

            let ranked = normalizedWeights.sorted { $0.value > $1.value }
            guard let dominant = ranked.first?.key else { return .balanced }
            switch dominant {
            case "Culture": return .culture
            case "Food": return .food
            case "Nature": return .nature
            case "Beach": return .beach
            default: return .balanced
            }
        }
        set {
            styleWeights = newValue.weights
        }
    }

    var budgetSummary: String {
        "€\(Int(budgetMin)) - €\(Int(budgetMax))"
    }

    var ecoSummary: String {
        "\(Int((ecoSensitivity * 100).rounded()))%"
    }

    var peopleSummary: String {
        "\(peopleDefault)"
    }

    var seasonsSummary: String {
        guard !preferredSeasons.isEmpty else { return Self.unsetLabel }
        if preferredSeasons.count == 4 { return L10n.tr("All year") }
        return preferredSeasons.sorted().map(Self.seasonTitle(for:)).joined(separator: ", ")
    }

    var styleSummary: String {
        let summary = normalized(weights: styleWeights)
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { Self.styleCategoryTitle(for: $0.key) }
            .joined(separator: " + ")
        return summary.isEmpty ? L10n.tr("Balanced") : summary
    }
}
