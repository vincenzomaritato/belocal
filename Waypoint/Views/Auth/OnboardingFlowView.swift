import Foundation
import MapKit
import SwiftData
import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var homeViewModel: HomeViewModel
    let onCompleted: () -> Void

    @State private var currentStep: Step = .identity
    @State private var stepDirection: StepDirection = .forward
    @State private var hasLoadedDraft = false

    @State private var profileName = ""
    @State private var peopleDefault = 2
    @State private var budgetPreset: SettingsViewModel.BudgetPreset = .comfort
    @State private var selectedSeasons: Set<String> = ["Spring", "Autumn"]
    @State private var stylePreset: SettingsViewModel.StylePreset = .balanced
    @State private var ecoPreset: SettingsViewModel.EcoPreset = .balanced

    @State private var homeLocationLabel = "Rome, Italy"
    @State private var homeCity = "Rome"
    @State private var homeCountry = "Italy"
    @State private var homeLatitude = TravelDistanceCalculator.defaultHomeLatitude
    @State private var homeLongitude = TravelDistanceCalculator.defaultHomeLongitude
    @State private var homeSearchQuery = ""
    @State private var homeSearchResults: [HomeLocationSearchResult] = []
    @State private var isSearchingCity = false
    @State private var homeSearchTask: Task<Void, Never>?

    @State private var isSaving = false
    @State private var errorMessage: String?

    private let seasons = ["Spring", "Summer", "Autumn", "Winter"]

    private enum Step: Int, CaseIterable, Identifiable {
        case identity
        case home
        case budget
        case seasons
        case style
        case sustainability

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .identity: return "Profile"
            case .home: return "Departure city"
            case .budget: return "Budget"
            case .seasons: return "Seasons"
            case .style: return "Travel style"
            case .sustainability: return "Sustainability"
            }
        }

        var subtitle: String {
            switch self {
            case .identity:
                return "Let's define who you are and how many people you usually travel with."
            case .home:
                return "We'll use your home base to estimate distance and environmental impact."
            case .budget:
                return "Pick a budget range for more accurate recommendations."
            case .seasons:
                return "Tell us when you prefer to travel during the year."
            case .style:
                return "Set the editorial direction for your suggestions."
            case .sustainability:
                return "Final step: sustainability priority and profile summary."
            }
        }
    }

    private enum StepDirection {
        case forward
        case backward
    }

    var body: some View {
        ZStack {
            AuthBackgroundView()
            onboardingMotionLayer

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        ZStack {
                            currentStepView
                                .id(currentStep)
                                .transition(stepTransition)
                        }
                        .animation(
                            .spring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.15),
                            value: currentStep
                        )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .tint(.blue)
        .safeAreaInset(edge: .bottom) {
            bottomActions
        }
        .task {
            loadDraftIfNeeded()
        }
        .onDisappear {
            homeSearchTask?.cancel()
        }
    }

    private var onboardingMotionLayer: some View {
        let stepFactor = CGFloat(currentStep.rawValue)

        return ZStack {
            Circle()
                .fill(Color.blue.opacity(0.09))
                .frame(width: 250, height: 250)
                .blur(radius: 26)
                .offset(x: 120 - (stepFactor * 9), y: -210 + (stepFactor * 12))
                .scaleEffect(stepDirection == .forward ? 1.015 : 0.985)

            Circle()
                .fill(Color.teal.opacity(0.08))
                .frame(width: 230, height: 230)
                .blur(radius: 28)
                .offset(x: -120 + (stepFactor * 8), y: 250 - (stepFactor * 10))
                .scaleEffect(stepDirection == .forward ? 0.985 : 1.015)
        }
        .animation(.easeInOut(duration: 0.48), value: currentStep)
        .allowsHitTesting(false)
    }

    private var stepTransition: AnyTransition {
        switch stepDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.95, anchor: .trailing)),
                removal: .move(edge: .leading)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 1.03, anchor: .leading))
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.95, anchor: .leading)),
                removal: .move(edge: .trailing)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 1.03, anchor: .trailing))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(8)
                    .background(Circle().fill(.ultraThinMaterial))
                    .accessibilityHidden(true)
                Text("Set up Waypoint")
                    .font(.title3.weight(.semibold))
            }

            Text(currentStep.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(currentStep.rawValue + 1), total: Double(Step.allCases.count))
                .progressViewStyle(.linear)
                .tint(.blue)

            HStack {
                Text("Step \(currentStep.rawValue + 1) of \(Step.allCases.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(currentStep.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch currentStep {
        case .identity:
            identityStep
        case .home:
            homeStep
        case .budget:
            budgetStep
        case .seasons:
            seasonsStep
        case .style:
            styleStep
        case .sustainability:
            sustainabilityStep
        }
    }

    private var identityStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("What should we call you?")
                    .font(.headline)

                TextField("e.g. Alex", text: $profileName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Name")
                    .accessibilityHint("Enter the name used for your travel profile")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground).opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Travelers per trip")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(peopleDefault)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.blue)
                    }

                    Stepper(value: $peopleDefault, in: 1...10) {
                        Text(peopleDefault == 1 ? "You usually travel solo" : "You usually travel with \(peopleDefault)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var homeStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Where do you usually depart from?")
                    .font(.headline)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Search a city", text: $homeSearchQuery)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Search departure city")
                        .accessibilityHint("Type a city and select one result")
                        .onChange(of: homeSearchQuery) { _, newValue in
                            scheduleHomeSearch(for: newValue)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground).opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                if isSearchingCity {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !homeSearchResults.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(homeSearchResults) { result in
                            Button {
                                applyHomeLocation(result)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .foregroundStyle(.primary)
                                        Text(result.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if homeLocationLabel == result.fullLabel {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Set departure city to \(result.fullLabel)")
                            .accessibilityAddTraits(homeLocationLabel == result.fullLabel ? .isSelected : [])
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected location")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(homeLocationLabel)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.blue.opacity(0.11))
                )

                Text("This sets your feedback perspective: Local in \(homeLocationLabel), Traveler in other destinations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var budgetStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("What's your typical budget per trip?")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(SettingsViewModel.BudgetPreset.allCases) { preset in
                        SelectableCard(
                            isSelected: budgetPreset == preset,
                            title: preset.title,
                            subtitle: preset.subtitle,
                            icon: budgetIcon(for: preset)
                        ) {
                            budgetPreset = preset
                        }
                    }
                }
            }
        }
    }

    private var seasonsStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("When do you prefer to travel?")
                    .font(.headline)

                FlexibleChipWrap(items: seasons) { season in
                    SelectableChip(
                        title: season,
                        isSelected: selectedSeasons.contains(season)
                    ) {
                        if selectedSeasons.contains(season) {
                            selectedSeasons.remove(season)
                        } else {
                            selectedSeasons.insert(season)
                        }
                    }
                }

                Text(selectedSeasons.isEmpty ? "Select at least one season." : "Selected: \(selectedSeasons.sorted().joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(selectedSeasons.isEmpty ? .red : .secondary)
            }
        }
    }

    private var styleStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("What kind of experience are you looking for?")
                    .font(.headline)

                ForEach(SettingsViewModel.StylePreset.allCases) { preset in
                    Button {
                        stylePreset = preset
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(stylePreset == preset ? Color.blue.opacity(0.2) : Color.primary.opacity(0.08))
                                Image(systemName: styleIcon(for: preset))
                                    .foregroundStyle(stylePreset == preset ? .blue : .secondary)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(styleSubtitle(for: preset))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if stylePreset == preset {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .accessibilityHidden(true)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(stylePreset == preset ? Color.blue.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(preset.title) style")
                    .accessibilityValue(stylePreset == preset ? "Selected" : "Not selected")
                    .accessibilityHint(styleSubtitle(for: preset))
                    .accessibilityAddTraits(stylePreset == preset ? .isSelected : [])
                }
            }
        }
    }

    private var sustainabilityStep: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Sustainability priority")
                    .font(.headline)

                HStack(spacing: 8) {
                    ForEach(SettingsViewModel.EcoPreset.allCases) { preset in
                        Button {
                            ecoPreset = preset
                        } label: {
                            VStack(spacing: 4) {
                                Text(preset.title)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(Int((preset.value * 100).rounded()))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(ecoPreset == preset ? Color.blue.opacity(0.18) : Color(uiColor: .tertiarySystemGroupedBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(ecoPreset == preset ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(preset.title) sustainability preference")
                        .accessibilityValue(ecoPreset == preset ? "Selected" : "Not selected")
                        .accessibilityHint("\(Int((preset.value * 100).rounded())) percent priority")
                        .accessibilityAddTraits(ecoPreset == preset ? .isSelected : [])
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.subheadline.weight(.bold))

                    summaryRow(label: "Name", value: profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Traveler" : profileName)
                    summaryRow(label: "Travelers", value: "\(peopleDefault)")
                    summaryRow(label: "Departure", value: homeLocationLabel)
                    summaryRow(label: "Budget", value: budgetPreset.subtitle)
                    summaryRow(label: "Seasons", value: selectedSeasons.sorted().joined(separator: ", "))
                    summaryRow(label: "Style", value: stylePreset.title)
                    summaryRow(label: "Eco", value: ecoPreset.title)
                }
            }
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Divider()

            HStack(spacing: 10) {
                Button {
                    goBack()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(currentStep == .identity || isSaving)

                Button {
                    goForward()
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(currentStep == .sustainability ? "Complete profile" : "Continue")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!canProceed || isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var canProceed: Bool {
        switch currentStep {
        case .identity:
            return profileName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case .seasons:
            return !selectedSeasons.isEmpty
        default:
            return true
        }
    }

    private func goBack() {
        guard let previous = Step(rawValue: currentStep.rawValue - 1) else { return }
        stepDirection = .backward
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            currentStep = previous
        }
    }

    private func goForward() {
        errorMessage = nil
        stepDirection = .forward

        if let next = Step(rawValue: currentStep.rawValue + 1) {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                currentStep = next
            }
        } else {
            saveProfile()
        }
    }

    private func saveProfile() {
        guard !isSaving else { return }
        isSaving = true

        let resolvedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = resolvedName.isEmpty ? "Traveler" : resolvedName

        var profile = homeViewModel.userProfile
        if profile == nil {
            profile = UserProfile(
                name: finalName,
                homeCity: homeCity,
                homeCountry: homeCountry,
                budgetMin: budgetPreset.range.lowerBound,
                budgetMax: budgetPreset.range.upperBound,
                preferredSeasons: Array(selectedSeasons).sorted(),
                travelStyleWeights: stylePreset.weights,
                ecoSensitivity: ecoPreset.value,
                peopleDefault: peopleDefault,
                homeLatitude: homeLatitude,
                homeLongitude: homeLongitude
            )
            if let profile {
                modelContext.insert(profile)
            }
        }

        guard let profile else {
            errorMessage = "Unable to prepare your profile."
            isSaving = false
            return
        }

        profile.name = finalName
        profile.peopleDefault = peopleDefault
        profile.budgetMin = budgetPreset.range.lowerBound
        profile.budgetMax = budgetPreset.range.upperBound
        profile.preferredSeasons = Array(selectedSeasons).sorted()
        profile.travelStyleWeights = stylePreset.weights
        profile.ecoSensitivity = ecoPreset.value
        profile.homeCity = homeCity
        profile.homeCountry = homeCountry
        profile.homeLatitude = homeLatitude
        profile.homeLongitude = homeLongitude

        do {
            try modelContext.save()
            bootstrap.settingsStore.completeOnboarding()
            homeViewModel.load(context: modelContext, bootstrap: bootstrap)
            isSaving = false
            onCompleted()
        } catch {
            errorMessage = "Couldn't save your profile."
            isSaving = false
        }
    }

    private func loadDraftIfNeeded() {
        guard !hasLoadedDraft else { return }
        hasLoadedDraft = true

        if homeViewModel.userProfile == nil {
            bootstrap.prepare(context: modelContext)
            homeViewModel.load(context: modelContext, bootstrap: bootstrap)
        }

        guard let profile = homeViewModel.userProfile else { return }

        profileName = profile.name
        peopleDefault = profile.peopleDefault

        budgetPreset = SettingsViewModel.BudgetPreset.allCases.min { lhs, rhs in
            let lhsScore = abs(lhs.range.lowerBound - profile.budgetMin) + abs(lhs.range.upperBound - profile.budgetMax)
            let rhsScore = abs(rhs.range.lowerBound - profile.budgetMin) + abs(rhs.range.upperBound - profile.budgetMax)
            return lhsScore < rhsScore
        } ?? .comfort

        let existingSeasons = Set(profile.preferredSeasons)
        selectedSeasons = existingSeasons.isEmpty ? ["Spring", "Autumn"] : existingSeasons

        let normalizedStyle = normalized(weights: profile.travelStyleWeights)
        let rankedStyle = normalizedStyle.sorted { $0.value > $1.value }.first?.key
        switch rankedStyle {
        case "Culture": stylePreset = .culture
        case "Food": stylePreset = .food
        case "Nature": stylePreset = .nature
        case "Beach": stylePreset = .beach
        default: stylePreset = .balanced
        }

        ecoPreset = SettingsViewModel.EcoPreset.allCases.min {
            abs($0.value - profile.ecoSensitivity) < abs($1.value - profile.ecoSensitivity)
        } ?? .balanced

        homeLatitude = profile.homeLatitude
        homeLongitude = profile.homeLongitude
        homeCity = profile.homeCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Rome" : profile.homeCity
        homeCountry = profile.homeCountry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Italy" : profile.homeCountry
        homeLocationLabel = defaultHomeLabel(for: profile)
    }

    private func normalized(weights: [String: Double]) -> [String: Double] {
        let sum = weights.values.reduce(0, +)
        guard sum > 0 else { return [:] }
        return Dictionary(uniqueKeysWithValues: weights.map { ($0.key, $0.value / sum) })
    }

    private func defaultHomeLabel(for profile: UserProfile) -> String {
        let normalizedCity = profile.homeCity.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCountry = profile.homeCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        let textual = [normalizedCity, normalizedCountry].filter { !$0.isEmpty }.joined(separator: ", ")
        if !textual.isEmpty {
            return textual
        }

        let isDefaultRome =
            abs(profile.homeLatitude - TravelDistanceCalculator.defaultHomeLatitude) < 0.0001 &&
            abs(profile.homeLongitude - TravelDistanceCalculator.defaultHomeLongitude) < 0.0001

        if isDefaultRome {
            return "Rome, Italy"
        }

        return String(format: "%.2f, %.2f", profile.homeLatitude, profile.homeLongitude)
    }

    private func scheduleHomeSearch(for query: String) {
        homeSearchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            homeSearchResults = []
            isSearchingCity = false
            return
        }

        homeSearchTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isSearchingCity = true
            }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = .address

            do {
                let response = try await MKLocalSearch(request: request).start()
                let mapped = mapResults(response.mapItems)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    homeSearchResults = mapped
                    isSearchingCity = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    homeSearchResults = []
                    isSearchingCity = false
                }
            }
        }
    }

    private func mapResults(_ items: [MKMapItem]) -> [HomeLocationSearchResult] {
        var unique = Set<String>()

        return items.compactMap { item in
            let city = item.addressRepresentations?.cityName
                ?? item.addressRepresentations?.cityWithContext(.short)
                ?? item.name
                ?? ""
            guard !city.isEmpty else { return nil }

            let country = item.addressRepresentations?.regionName ?? ""
            let key = "\(city.lowercased())|\(country.lowercased())"
            guard unique.insert(key).inserted else { return nil }

            let coordinate = item.location.coordinate
            return HomeLocationSearchResult(
                id: key,
                title: city,
                subtitle: country,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
        .prefix(6)
        .map { $0 }
    }

    private func applyHomeLocation(_ result: HomeLocationSearchResult) {
        homeLatitude = result.latitude
        homeLongitude = result.longitude
        homeCity = result.title
        homeCountry = result.subtitle
        homeLocationLabel = result.fullLabel
    }

    private func budgetIcon(for preset: SettingsViewModel.BudgetPreset) -> String {
        switch preset {
        case .essential: return "wallet.pass"
        case .comfort: return "creditcard"
        case .premium: return "sparkles"
        case .luxury: return "crown"
        }
    }

    private func styleIcon(for preset: SettingsViewModel.StylePreset) -> String {
        switch preset {
        case .balanced: return "slider.horizontal.3"
        case .culture: return "building.columns"
        case .food: return "fork.knife"
        case .nature: return "leaf"
        case .beach: return "sun.max"
        }
    }

    private func styleSubtitle(for preset: SettingsViewModel.StylePreset) -> String {
        switch preset {
        case .balanced:
            return "Balanced mix across culture, food, and outdoor."
        case .culture:
            return "Museums, heritage, and iconic urban scenes."
        case .food:
            return "Culinary experiences and authentic local spots."
        case .nature:
            return "Landscapes, hiking, and green destinations."
        case .beach:
            return "Coasts, relaxation, and sea-view rhythm."
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }
}

private struct HomeLocationSearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var fullLabel: String {
        [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private struct SelectableCard: View {
    let isSelected: Bool
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isSelected ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .blue : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.blue.opacity(0.15) : Color(uiColor: .tertiarySystemGroupedBackground))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? Color.blue.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Double-tap to toggle this season")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OnboardingCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 8)
    }
}

private struct FlexibleChipWrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chunked(items, by: 2), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { item in
                        content(item)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chunked(_ source: [String], by size: Int) -> [[String]] {
        guard size > 0 else { return [source] }
        var chunks: [[String]] = []
        var index = 0

        while index < source.count {
            let end = min(index + size, source.count)
            chunks.append(Array(source[index..<end]))
            index += size
        }

        return chunks
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.onboarding") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext
    bootstrap.prepare(context: context)

    let homeViewModel = HomeViewModel()
    homeViewModel.load(context: context, bootstrap: bootstrap)

    return OnboardingFlowView(homeViewModel: homeViewModel, onCompleted: {})
        .environment(bootstrap)
        .modelContainer(container)
}
