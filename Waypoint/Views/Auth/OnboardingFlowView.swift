import Foundation
import MapKit
import SwiftData
import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppBootstrap.self) private var bootstrap
    @Environment(\.colorScheme) private var colorScheme

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

    @State private var homeLocationLabel = L10n.tr("Not set")
    @State private var homeCity = ""
    @State private var homeCountry = ""
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
            case .identity:
                return L10n.tr("Create your travel profile")
            case .home:
                return L10n.tr("Set your departure city")
            case .budget:
                return L10n.tr("Choose your budget rhythm")
            case .seasons:
                return L10n.tr("Pick your favorite travel moments")
            case .style:
                return L10n.tr("Shape the kind of trips you want")
            case .sustainability:
                return L10n.tr("Finalize your preferences")
            }
        }

        var subtitle: String {
            switch self {
            case .identity:
                return L10n.tr("A few answers are enough to make recommendations feel personal from the first search.")
            case .home:
                return L10n.tr("We use your base city to calculate distance, relevance, and perspective in the app.")
            case .budget:
                return L10n.tr("This keeps suggestions realistic instead of aspirational.")
            case .seasons:
                return L10n.tr("Seasonality helps us surface destinations when they actually fit your timing.")
            case .style:
                return L10n.tr("Tell us what kind of experience should lead the selection.")
            case .sustainability:
                return L10n.tr("One last choice, then we save everything and unlock your personalized feed.")
            }
        }

        var symbol: String {
            switch self {
            case .identity: return "person.crop.circle"
            case .home: return "location.circle"
            case .budget: return "creditcard.circle"
            case .seasons: return "calendar.circle"
            case .style: return "sparkles"
            case .sustainability: return "leaf.circle"
            }
        }

        var prompt: String {
            switch self {
            case .identity:
                return L10n.tr("How should BeLocal introduce you?")
            case .home:
                return L10n.tr("Where do you usually start your trips?")
            case .budget:
                return L10n.tr("What budget range feels natural for you?")
            case .seasons:
                return L10n.tr("When do you most enjoy traveling?")
            case .style:
                return L10n.tr("What should be prioritized in your recommendations?")
            case .sustainability:
                return L10n.tr("How much weight should sustainability have?")
            }
        }
    }

    private enum StepDirection {
        case forward
        case backward
    }

    private var accent: Color {
        .accentColor
    }

    private var accentSoft: Color {
        accent.opacity(0.12)
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var primaryText: Color {
        isDarkMode ? .white : .black
    }

    private var secondaryText: Color {
        isDarkMode ? Color.white.opacity(0.64) : Color.black.opacity(0.56)
    }

    private var pageGradient: [Color] {
        if isDarkMode {
            return [
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color(red: 0.09, green: 0.10, blue: 0.13),
                Color(red: 0.07, green: 0.10, blue: 0.13)
            ]
        }

        return [
            Color(red: 0.95, green: 0.96, blue: 0.97),
            Color(red: 0.93, green: 0.95, blue: 0.97),
            Color(red: 0.92, green: 0.95, blue: 0.97)
        ]
    }

    private var sheetBackground: Color {
        isDarkMode ? Color(red: 0.10, green: 0.11, blue: 0.14) : Color(red: 0.99, green: 0.99, blue: 0.99)
    }

    private var surfaceFill: Color {
        isDarkMode ? Color.white.opacity(0.06) : Color.white
    }

    private var softFill: Color {
        isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
    }

    private var borderColor: Color {
        isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                onboardingBackground
                onboardingMotionLayer(size: proxy.size)

                VStack(spacing: 0) {
                    Spacer(minLength: max(54, proxy.size.height * 0.08))

                    onboardingHero
                        .padding(.bottom, 28)
                        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: currentStep.rawValue)

                    onboardingSheet
                        .padding(.horizontal, 24)
                        .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 10))
                }
            }
        }
        .ignoresSafeArea()
        .tint(accent)
        .task {
            loadDraftIfNeeded()
        }
        .onDisappear {
            homeSearchTask?.cancel()
        }
    }

    private var onboardingBackground: some View {
        LinearGradient(
            colors: pageGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func onboardingMotionLayer(size: CGSize) -> some View {
        let factor = CGFloat(currentStep.rawValue)

        return ZStack {
            Circle()
                .fill(isDarkMode ? Color.white.opacity(0.08) : Color.white.opacity(0.7))
                .frame(width: size.width * 0.92, height: size.width * 0.92)
                .blur(radius: 34)
                .offset(x: 24 - (factor * 10), y: -size.height * 0.2)

            Circle()
                .fill(accent.opacity(0.1))
                .frame(width: size.width * 0.54, height: size.width * 0.54)
                .blur(radius: 28)
                .offset(x: -72 + (factor * 8), y: 12 + (factor * 10))

            Circle()
                .fill(isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
                .frame(width: size.width * 0.42, height: size.width * 0.42)
                .blur(radius: 24)
                .offset(x: 92 - (factor * 12), y: size.height * 0.16)
        }
        .animation(.easeInOut(duration: 0.42), value: currentStep.rawValue)
        .allowsHitTesting(false)
    }

    private var onboardingHero: some View {
        ZStack {
            Circle()
                .fill(accent)
                .frame(width: 60, height: 60)
                .offset(x: -12, y: -4)

            Circle()
                .fill(surfaceFill)
                .frame(width: 74, height: 74)
                .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 10)

            Image(systemName: currentStep.symbol)
                .font(.system(size: 31, weight: .semibold))
                .foregroundStyle(accent)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private var onboardingSheet: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    sheetHeader

                    ZStack {
                        currentStepView
                            .id(currentStep)
                            .transition(stepTransition)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.88), value: currentStep)
                    .padding(.top, 24)

                    if let errorMessage {
                        errorBanner(errorMessage)
                            .padding(.top, 18)
                    }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 26)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomActions
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
        }
    }

    private var sheetHeader: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Personal onboarding"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(L10n.f("Step %d of %d", currentStep.rawValue + 1, Step.allCases.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)

                progressRail
                    .frame(width: 132)
            }

            VStack(spacing: 10) {
                Text(currentStep.title)
                    .font(.system(size: 33, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(primaryText)

                Text(currentStep.subtitle)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var progressRail: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases) { step in
                Capsule(style: .continuous)
                    .fill(step.rawValue <= currentStep.rawValue ? accent : (isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)))
                    .frame(height: 8)
            }
        }
    }

    private var stepTransition: AnyTransition {
        switch stepDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        }
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
        AssistantStepCard(prompt: currentStep.prompt) {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingInputField(
                    icon: "person",
                    prompt: L10n.tr("Your name"),
                    text: $profileName
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

                VStack(alignment: .leading, spacing: 14) {
                    Text(L10n.tr("How many people usually travel with you?"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)

                    HStack(spacing: 14) {
                        CounterButton(symbol: "minus") {
                            peopleDefault = max(1, peopleDefault - 1)
                        }
                        .disabled(peopleDefault == 1)

                        VStack(spacing: 4) {
                            Text("\(peopleDefault)")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(primaryText)

                            Text(
                                peopleDefault == 1
                                    ? L10n.tr("Solo by default")
                                    : L10n.f("%d travelers per trip", peopleDefault)
                            )
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        CounterButton(symbol: "plus") {
                            peopleDefault = min(10, peopleDefault + 1)
                        }
                        .disabled(peopleDefault == 10)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(surfaceFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                }

                AssistantInsightRow(
                    icon: "sparkles",
                    text: L10n.tr("This makes greetings, recommendations, and trip planning immediately more relevant.")
                )
            }
        }
    }

    private var homeStep: some View {
        AssistantStepCard(prompt: currentStep.prompt) {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingInputField(
                    icon: "magnifyingglass",
                    prompt: L10n.tr("Search a city"),
                    text: $homeSearchQuery
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .onChange(of: homeSearchQuery) { _, newValue in
                    scheduleHomeSearch(for: newValue)
                }

                if isSearchingCity {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(L10n.tr("Searching places"))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if !homeSearchResults.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(homeSearchResults) { result in
                            Button {
                                applyHomeLocation(result)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(primaryText)
                                        Text(result.subtitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)

                                    if homeLocationLabel == result.fullLabel {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .fill(surfaceFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                                        .strokeBorder(
                                            homeLocationLabel == result.fullLabel ? accent.opacity(0.38) : borderColor,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("Selected departure city"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(homeLocationLabel)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(primaryText)

                    Text(
                        homeLocationLabel == L10n.tr("Not set")
                            ? L10n.tr("Set a departure city to personalize local versus traveler feedback.")
                            : L10n.f("We will frame feedback as Local in %@ and Traveler elsewhere.", homeLocationLabel)
                    )
                        .font(.footnote)
                        .foregroundStyle(secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(accentSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(accent.opacity(0.18), lineWidth: 1)
                )
            }
        }
    }

    private var budgetStep: some View {
        AssistantStepCard(prompt: currentStep.prompt) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SettingsViewModel.BudgetPreset.allCases) { preset in
                    AssistantSelectionCard(
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

    private var seasonsStep: some View {
        AssistantStepCard(prompt: currentStep.prompt) {
            VStack(alignment: .leading, spacing: 16) {
                FlexibleChipWrap(items: seasons) { season in
                    AssistantChip(
                        title: L10n.season(season),
                        isSelected: selectedSeasons.contains(season)
                    ) {
                        if selectedSeasons.contains(season) {
                            selectedSeasons.remove(season)
                        } else {
                            selectedSeasons.insert(season)
                        }
                    }
                }

                Text(
                    selectedSeasons.isEmpty
                        ? L10n.tr("Select at least one season to continue.")
                        : L10n.f("Selected: %@", selectedSeasons.sorted().map(L10n.season).joined(separator: ", "))
                )
                .font(.footnote.weight(.medium))
                .foregroundStyle(selectedSeasons.isEmpty ? Color.red : .secondary)
            }
        }
    }

    private var styleStep: some View {
        AssistantStepCard(prompt: currentStep.prompt) {
            VStack(spacing: 10) {
                ForEach(SettingsViewModel.StylePreset.allCases) { preset in
                    styleOptionRow(preset)
                }
            }
        }
    }

    private var sustainabilityStep: some View {
        AssistantStepCard(prompt: currentStep.prompt) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    ForEach(SettingsViewModel.EcoPreset.allCases) { preset in
                        Button {
                            ecoPreset = preset
                        } label: {
                            VStack(spacing: 6) {
                                Text(preset.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ecoPreset == preset ? accent : primaryText)

                                Text(L10n.f("%d%%", Int((preset.value * 100).rounded())))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(ecoPreset == preset ? accentSoft : surfaceFill)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .strokeBorder(ecoPreset == preset ? accent.opacity(0.32) : borderColor, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.title)
                        .accessibilityValue(ecoPreset == preset ? L10n.tr("Selected") : L10n.tr("Not selected"))
                        .accessibilityHint(L10n.f("%d percent sustainability preference", Int((preset.value * 100).rounded())))
                        .accessibilityAddTraits(ecoPreset == preset ? .isSelected : [])
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.tr("Profile summary"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        summaryRow(label: L10n.tr("Name"), value: profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.tr("Traveler") : profileName)
                        summaryRow(label: L10n.tr("Travelers"), value: "\(peopleDefault)")
                        summaryRow(label: L10n.tr("Departure"), value: homeLocationLabel)
                        summaryRow(label: L10n.tr("Budget"), value: budgetPreset.subtitle)
                        summaryRow(label: L10n.tr("Seasons"), value: selectedSeasons.sorted().map(L10n.season).joined(separator: ", "))
                        summaryRow(label: L10n.tr("Style"), value: stylePreset.title)
                        summaryRow(label: L10n.tr("Eco"), value: ecoPreset.title)
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(surfaceFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.red)

            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.red)
                .multilineTextAlignment(.leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }

    private var bottomActions: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentStep == .sustainability ? L10n.tr("Ready to save") : L10n.tr("Keep going"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)

                    Text(
                        currentStep == .sustainability
                            ? L10n.tr("We will save your profile and enter the app.")
                            : L10n.tr("Each answer sharpens your feed, maps, and recommendations.")
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 56, height: 56)
                        .foregroundStyle(primaryText)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(softFill)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.tr("Go back"))
                .accessibilityHint(L10n.tr("Returns to the previous onboarding step"))
                .opacity(currentStep == .identity || isSaving ? 0.42 : 1)
                .disabled(currentStep == .identity || isSaving)

                Button {
                    goForward()
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(currentStep == .sustainability ? L10n.tr("Complete profile") : L10n.tr("Continue"))
                            .font(.system(size: 18, weight: .semibold))

                        if !isSaving {
                            Image(systemName: currentStep == .sustainability ? "checkmark" : "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(!canProceed || isSaving ? accent.opacity(0.34) : accent)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(currentStep == .sustainability ? L10n.tr("Saves your profile and enters the app") : L10n.tr("Moves to the next onboarding step"))
                .disabled(!canProceed || isSaving)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
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
        let finalName = resolvedName.isEmpty ? L10n.tr("Traveler") : resolvedName

        var profile = homeViewModel.userProfile
        if profile == nil {
            profile = UserProfile(
                authUserId: bootstrap.settingsStore.authenticatedUserID,
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
            errorMessage = L10n.tr("Unable to prepare your profile.")
            isSaving = false
            return
        }

        profile.name = finalName
        profile.authUserId = bootstrap.settingsStore.authenticatedUserID
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
            if bootstrap.supabaseSyncService.config.isConfigured {
                bootstrap.syncManager.enqueue(
                    type: .upsertProfile,
                    payload: [
                        "profileId": profile.id.uuidString,
                        "authUserId": bootstrap.settingsStore.authenticatedUserID,
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
                    ],
                    context: modelContext
                )
            }
            bootstrap.settingsStore.completeOnboarding()
            homeViewModel.load(context: modelContext, bootstrap: bootstrap)
            isSaving = false
            onCompleted()
        } catch {
            errorMessage = L10n.tr("Couldn't save your profile.")
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
        homeCity = profile.homeCity
        homeCountry = profile.homeCountry
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

        return L10n.tr("Not set")
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
            return L10n.tr("Balanced mix across culture, food, and outdoor.")
        case .culture:
            return L10n.tr("Museums, heritage, and iconic urban scenes.")
        case .food:
            return L10n.tr("Culinary experiences and authentic local spots.")
        case .nature:
            return L10n.tr("Landscapes, hiking, and green destinations.")
        case .beach:
            return L10n.tr("Coasts, relaxation, and sea-view rhythm.")
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func styleOptionRow(_ preset: SettingsViewModel.StylePreset) -> some View {
        let isSelected = stylePreset == preset
        let subtitle = styleSubtitle(for: preset)

        return Button {
            stylePreset = preset
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(isSelected ? accentSoft : softFill)

                    Image(systemName: styleIcon(for: preset))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : .secondary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryText)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(isSelected ? accentSoft : surfaceFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.34) : borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.title)
        .accessibilityValue(isSelected ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

private struct AssistantStepCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let prompt: String
    let content: Content

    init(prompt: String, @ViewBuilder content: () -> Content) {
        self.prompt = prompt
        self.content = content()
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(prompt)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isDarkMode ? .white : .black)

            content
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.04) : Color(red: 0.985, green: 0.985, blue: 0.985))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct OnboardingInputField: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let prompt: String
    @Binding var text: String

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.56) : Color.black.opacity(0.52))
                .frame(width: 22)

            TextField(prompt, text: $text)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isDarkMode ? .white : .black)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(isDarkMode ? Color.white.opacity(0.14) : Color.black.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct AssistantSelectionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let isSelected: Bool
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    private var accent: Color {
        .accentColor
    }

    private var accentSoft: Color {
        accent.opacity(0.12)
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isSelected ? accentSoft : (isDarkMode ? Color.white.opacity(0.05) : Color.black.opacity(0.04)))

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? accent : .secondary)
                }
                .frame(width: 40, height: 40)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDarkMode ? .white : .black)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(isSelected ? accentSoft : (isDarkMode ? Color.white.opacity(0.06) : Color.white))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.34) : (isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AssistantChip: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let isSelected: Bool
    let action: () -> Void

    private var accent: Color {
        .accentColor
    }

    private var accentSoft: Color {
        accent.opacity(0.12)
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? accent : (isDarkMode ? .white : .black))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? accentSoft : (isDarkMode ? Color.white.opacity(0.06) : Color.white))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(isSelected ? accent.opacity(0.34) : (isDarkMode ? Color.white.opacity(0.12) : Color.black.opacity(0.08)), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(L10n.tr("Double-tap to toggle this preference"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CounterButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let symbol: String
    let action: () -> Void

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isDarkMode ? .white : .black)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isDarkMode ? Color.white.opacity(0.06) : Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AssistantInsightRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let text: String

    private var accent: Color {
        .accentColor
    }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)

            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(isDarkMode ? Color.white.opacity(0.64) : Color.black.opacity(0.56))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(isDarkMode ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        )
    }
}

private struct FlexibleChipWrap<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(chunked(items, by: 2), id: \.self) { row in
                HStack(spacing: 10) {
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
