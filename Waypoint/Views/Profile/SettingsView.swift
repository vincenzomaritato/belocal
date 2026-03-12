import MapKit
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var homeViewModel: HomeViewModel
    @Bindable var settingsViewModel: SettingsViewModel

    @State private var showHomeCityPicker = false
    @State private var showSignOutConfirmation = false
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var liveRefreshTask: Task<Void, Never>?
    @State private var suppressAutoSave = true

    private let seasons = SettingsViewModel.seasonOrder

    var body: some View {
        NavigationStack {
            List {
                accountSection
                if isProfileIncomplete {
                    profileCompletionSection
                }
                travelProfileSection
                seasonsSection
                styleSection
                sessionSection

                if let saveMessage = settingsViewModel.saveMessage {
                    Section {
                        Label(saveMessage, systemImage: isSaveMessageError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(isSaveMessageError ? .red : .secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.tr("Settings"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showHomeCityPicker) {
                NavigationStack {
                    HomeLocationPickerView(settingsViewModel: settingsViewModel)
                }
            }
            .alert(L10n.tr("Sign Out"), isPresented: $showSignOutConfirmation) {
                Button(L10n.tr("Cancel"), role: .cancel) {}
                Button(L10n.tr("Sign Out"), role: .destructive) {
                    performSignOut()
                }
            } message: {
                Text(L10n.tr("You will return to the login flow and need to sign in again to access your profile."))
            }
            .onAppear {
                settingsViewModel.load(from: homeViewModel.userProfile)
                suppressAutoSave = true
                autoSaveTask?.cancel()
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    suppressAutoSave = false
                }
            }
            .onDisappear {
                autoSaveTask?.cancel()
                liveRefreshTask?.cancel()
                if !suppressAutoSave {
                    saveSettings()
                    homeViewModel.refreshRecommendations(bootstrap: bootstrap)
                }
            }
            .onChange(of: settingsViewModel.profileName) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.homeCity) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.homeCountry) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.homeLatitude) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.homeLongitude) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.budgetMin) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.budgetMax) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.ecoSensitivity) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.peopleDefault) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.preferredSeasons) { _, _ in
                scheduleAutoSave()
            }
            .onChange(of: settingsViewModel.styleWeights) { _, _ in
                scheduleAutoSave()
            }
        }
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 14) {
                profileAvatar
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("Profile"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(L10n.tr("Traveler"), text: $settingsViewModel.profileName)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .accessibilityLabel(L10n.tr("Profile"))
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var profileCompletionSection: some View {
        Section(L10n.tr("Complete your profile")) {
            Text(L10n.tr("Add your name and home city to improve recommendations and local/traveler feedback accuracy."))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if settingsViewModel.homeLocationLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                settingsViewModel.homeLocationLabel == SettingsViewModel.unsetLabel {
                Button(L10n.tr("Choose Home City")) {
                    showHomeCityPicker = true
                }
            }

            if settingsViewModel.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(L10n.tr("Use Traveler as name")) {
                    settingsViewModel.profileName = SettingsViewModel.defaultProfileName
                }
            }
        }
    }

    private var travelProfileSection: some View {
        Section {
            Button {
                showHomeCityPicker = true
            } label: {
                settingRow(
                    icon: "house.fill",
                    iconColor: .teal,
                    title: "Home City",
                    value: settingsViewModel.homeLocationLabel,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Home City"))
            .accessibilityValue(settingsViewModel.homeLocationLabel)
            .accessibilityHint(L10n.tr("Double-tap to change home location"))

            HStack(spacing: 12) {
                settingIcon(symbol: "creditcard.fill", color: .indigo)
                Text(L10n.tr("Budget"))
                Spacer()
                Menu {
                    Picker("", selection: Binding(
                        get: { settingsViewModel.selectedBudgetPreset },
                        set: { settingsViewModel.selectedBudgetPreset = $0 }
                    )) {
                        ForEach(SettingsViewModel.BudgetPreset.allCases) { preset in
                            Text("\(preset.title) · \(preset.subtitle)").tag(preset)
                        }
                    }
                    .labelsHidden()
                } label: {
                    HStack(spacing: 6) {
                        Text(settingsViewModel.selectedBudgetPreset.title)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel(L10n.tr("Budget preset"))
                .accessibilityValue(settingsViewModel.selectedBudgetPreset.title)
                .accessibilityHint(L10n.tr("Double-tap to choose a budget profile"))
            }

            HStack(spacing: 12) {
                settingIcon(symbol: "leaf.fill", color: .green)
                Text(L10n.tr("Sustainability"))
                Spacer()
                Menu {
                    Picker("", selection: Binding(
                        get: { settingsViewModel.selectedEcoPreset },
                        set: { settingsViewModel.selectedEcoPreset = $0 }
                    )) {
                        ForEach(SettingsViewModel.EcoPreset.allCases) { preset in
                            Text("\(preset.title) · \(Int((preset.value * 100).rounded()))%").tag(preset)
                        }
                    }
                    .labelsHidden()
                } label: {
                    HStack(spacing: 6) {
                        Text(settingsViewModel.selectedEcoPreset.title)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel(L10n.tr("Sustainability preset"))
                .accessibilityValue(settingsViewModel.selectedEcoPreset.title)
                .accessibilityHint(L10n.tr("Double-tap to choose an environmental preference"))
            }
        } header: {
            Text(L10n.tr("Travel Profile"))
        } footer: {
            Text("\(settingsViewModel.selectedBudgetPreset.subtitle). \(budgetDetailText)\n\(sustainabilityDetailText)\n\(feedbackPerspectiveHint)")
        }
    }

    private var seasonsSection: some View {
        Section {
            ForEach(seasons, id: \.self) { season in
                Toggle(SettingsViewModel.seasonTitle(for: season), isOn: seasonBinding(for: season))
            }
        } header: {
            Text(L10n.tr("Preferred Seasons"))
        }
    }

    private var styleSection: some View {
        Section {
            Text(L10n.tr("Choose the personality of your suggestions."))
                .font(.footnote)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(SettingsViewModel.StylePreset.allCases) { preset in
                    Button {
                        settingsViewModel.selectedStylePreset = preset
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: styleIcon(for: preset))
                                    .font(.footnote.weight(.semibold))
                                Text(preset.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                if settingsViewModel.selectedStylePreset == preset {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.accent)
                                }
                            }
                            Text(styleDetail(for: preset))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    settingsViewModel.selectedStylePreset == preset
                                    ? Color.accentColor.opacity(0.14)
                                    : Color(uiColor: .tertiarySystemGroupedBackground)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.f("%@ style", preset.title))
                    .accessibilityValue(settingsViewModel.selectedStylePreset == preset ? L10n.tr("Selected") : L10n.tr("Not selected"))
                    .accessibilityHint(styleDetail(for: preset))
                    .accessibilityAddTraits(settingsViewModel.selectedStylePreset == preset ? .isSelected : [])
                }
            }
        } header: {
            Text(L10n.tr("Travel Style"))
        } footer: {
            Text(L10n.f("Current: %@. %@", settingsViewModel.selectedStylePreset.title, styleDetail(for: settingsViewModel.selectedStylePreset)))
        }
    }

    private var sessionSection: some View {
        Section {
            Button(L10n.tr("Sign Out"), role: .destructive) {
                showSignOutConfirmation = true
            }
        } header: {
            Text(L10n.tr("Session"))
        } footer: {
            Text(L10n.tr("Sign out from this account on this device."))
        }
    }

    private var profileAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.cyan.opacity(0.85), Color.blue.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(profileInitials)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(width: 58, height: 58)
        .accessibilityHidden(true)
    }

    private var profileInitials: String {
        let source = settingsViewModel.profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return "TR" }
        let parts = source.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private func seasonBinding(for season: String) -> Binding<Bool> {
        Binding(
            get: { settingsViewModel.preferredSeasons.contains(season) },
            set: { enabled in
                if enabled {
                    settingsViewModel.preferredSeasons.insert(season)
                } else {
                    settingsViewModel.preferredSeasons.remove(season)
                }
            }
        )
    }

    private func saveSettings() {
        settingsViewModel.save(
            to: homeViewModel.userProfile,
            context: modelContext,
            homeViewModel: homeViewModel,
            bootstrap: bootstrap
        )
    }

    private func scheduleAutoSave() {
        guard !suppressAutoSave else { return }

        scheduleLiveRecommendationRefresh()

        autoSaveTask?.cancel()
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            saveSettings()
        }
    }

    private func scheduleLiveRecommendationRefresh() {
        settingsViewModel.applyDraft(to: homeViewModel.userProfile)

        liveRefreshTask?.cancel()
        liveRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            homeViewModel.refreshRecommendations(bootstrap: bootstrap)
        }
    }

    private func performSignOut() {
        autoSaveTask?.cancel()
        liveRefreshTask?.cancel()
        suppressAutoSave = true
        bootstrap.settingsStore.signOut()
        dismiss()
    }

    private func settingIcon(symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
    }

    private func settingRow(
        icon: String,
        iconColor: Color,
        title: String,
        value: String,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            settingIcon(symbol: icon, color: iconColor)
            Text(L10n.tr(title))
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }

    private var budgetDetailText: String {
        switch settingsViewModel.selectedBudgetPreset {
        case .essential:
            return L10n.tr("Focused on value and lighter spending.")
        case .comfort:
            return L10n.tr("Balanced comfort for most trips.")
        case .premium:
            return L10n.tr("Higher quality stays and experiences.")
        case .luxury:
            return L10n.tr("Top-tier travel choices.")
        }
    }

    private var sustainabilityDetailText: String {
        switch settingsViewModel.selectedEcoPreset {
        case .low:
            return L10n.tr("Lower environmental constraints.")
        case .balanced:
            return L10n.tr("Balance between sustainability and flexibility.")
        case .high:
            return L10n.tr("Prioritizes low-impact options.")
        }
    }

    private func styleIcon(for preset: SettingsViewModel.StylePreset) -> String {
        switch preset {
        case .balanced: return "slider.horizontal.3"
        case .culture: return "building.columns.fill"
        case .food: return "fork.knife"
        case .nature: return "leaf.fill"
        case .beach: return "sun.max.fill"
        }
    }

    private func styleDetail(for preset: SettingsViewModel.StylePreset) -> String {
        switch preset {
        case .balanced:
            return L10n.tr("A versatile mix across all categories.")
        case .culture:
            return L10n.tr("Museums, heritage, art, and city identity.")
        case .food:
            return L10n.tr("Restaurants, local flavors, and culinary spots.")
        case .nature:
            return L10n.tr("Parks, landscapes, and outdoor experiences.")
        case .beach:
            return L10n.tr("Coastal destinations and sea-focused trips.")
        }
    }

    private var feedbackPerspectiveHint: String {
        let home = settingsViewModel.homeLocationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !home.isEmpty else {
            return L10n.tr("Your feedback is classified as Local around your home area and Traveler in other destinations.")
        }
        return L10n.f("Your feedback role is Local in %@ and Traveler in other destinations.", home)
    }

    private var isProfileIncomplete: Bool {
        let hasName = !settingsViewModel.profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let homeLabel = settingsViewModel.homeLocationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasHome = !homeLabel.isEmpty && homeLabel != SettingsViewModel.unsetLabel
        return !hasName || !hasHome
    }

    private var isSaveMessageError: Bool {
        guard settingsViewModel.saveMessage != nil else { return false }
        return settingsViewModel.saveMessageIsError
    }
}

private struct HomeLocationSearchResult: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
}

private struct HomeLocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var settingsViewModel: SettingsViewModel

    @State private var query = ""
    @State private var results: [HomeLocationSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                Button {
                    settingsViewModel.setHomeLocation(
                        latitude: TravelDistanceCalculator.defaultHomeLatitude,
                        longitude: TravelDistanceCalculator.defaultHomeLongitude,
                        city: "",
                        country: "",
                        label: L10n.tr("Not set")
                    )
                    dismiss()
                } label: {
                    Label(L10n.tr("Clear home city"), systemImage: "arrow.uturn.backward")
                }
            }

            Section(L10n.tr("Results")) {
                if isSearching {
                    HStack {
                        ProgressView()
                        Text(L10n.tr("Searching..."))
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(results) { item in
                    Button {
                        settingsViewModel.setHomeLocation(
                            latitude: item.latitude,
                            longitude: item.longitude,
                            city: item.title,
                            country: item.subtitle,
                            label: [item.title, item.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                        )
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundStyle(.primary)
                            Text(item.subtitle)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !isSearching && query.count >= 2 && results.isEmpty {
                    ContentUnavailableView(L10n.tr("No city found"), systemImage: "magnifyingglass", description: Text(L10n.tr("Try another name")))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.tr("Home City"))
        .searchable(text: $query, prompt: L10n.tr("Search city"))
        .onChange(of: query) { _, newValue in
            scheduleSearch(for: newValue)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func scheduleSearch(for text: String) {
        searchTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isSearching = true
            }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = .address

            do {
                let response = try await MKLocalSearch(request: request).start()
                let resolved = mapResults(from: response.mapItems)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    results = resolved
                    isSearching = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    results = []
                    isSearching = false
                }
            }
        }
    }

    private func mapResults(from items: [MKMapItem]) -> [HomeLocationSearchResult] {
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
        .prefix(20)
        .map { $0 }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.settings") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext
    bootstrap.prepare(context: context)

    let homeViewModel = HomeViewModel()
    homeViewModel.load(context: context, bootstrap: bootstrap)
    let settingsViewModel = SettingsViewModel()
    settingsViewModel.load(from: homeViewModel.userProfile)

    return SettingsView(homeViewModel: homeViewModel, settingsViewModel: settingsViewModel)
        .environment(bootstrap)
        .modelContainer(container)
}
