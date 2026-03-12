import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct AddTripSheetView: View {
    enum AddTripStep {
        case location
        case details
    }

    enum TravelIntent: String, CaseIterable {
        case been
        case wantToGo

        var label: String {
            switch self {
            case .been: return L10n.tr("Past trip")
            case .wantToGo: return L10n.tr("Future trip")
            }
        }
    }

    struct AppleCitySuggestion: Identifiable, Hashable {
        let name: String
        let country: String
        let region: String?
        let latitude: Double
        let longitude: Double

        var id: String {
            "\(name.lowercased())|\(country.lowercased())|\(latitude)|\(longitude)"
        }
    }

    enum Continent: String, CaseIterable, Hashable {
        case africa
        case europe
        case asia
        case northAmerica
        case southAmerica
        case oceania
        case antarctica
        case other

        var label: String {
            switch self {
            case .africa: return L10n.tr("Africa")
            case .europe: return L10n.tr("Europe")
            case .asia: return L10n.tr("Asia")
            case .northAmerica: return L10n.tr("North America")
            case .southAmerica: return L10n.tr("South America")
            case .oceania: return L10n.tr("Oceania")
            case .antarctica: return L10n.tr("Antarctica")
            case .other: return L10n.tr("Other")
            }
        }

        static var orderedCases: [Continent] {
            Self.allCases.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        }
    }

    struct CountryEntry: Identifiable, Hashable {
        let name: String
        let code: String
        let continent: Continent

        var id: String { code }
    }

    struct LocalCityEntry: Hashable {
        let name: String
        let asciiName: String
        let countryCode: String
        let latitude: Double
        let longitude: Double
        let population: Int
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var homeViewModel: HomeViewModel
    let onSaved: () -> Void

    @State private var travelIntent: TravelIntent = .been
    @State private var countryQuery = ""
    @State private var cityQuery = ""
    @State private var selectedCountry: String?
    @State private var selectedCity: AppleCitySuggestion?
    @State private var citySuggestions: [AppleCitySuggestion] = []
    @State private var isFetchingCities = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var citySearchTask: Task<Void, Never>?
    @State private var countrySearchRegion: MKCoordinateRegion?
    @State private var countryEnglishName: String?
    @State private var countryRegionTask: Task<Void, Never>?
    @State private var tripStartDate = Calendar.current.startOfDay(for: .now)
    @State private var tripEndDate = Calendar.current.date(byAdding: .day, value: 4, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var tripTransportType: TransportType = .plane
    @State private var tripPeople = 2
    @State private var tripBudget = 0.0
    @State private var didInitializeTripDefaults = false
    @State private var currentStep: AddTripStep = .location

    private static let countryEntries: [CountryEntry] = {
        let locale = Locale.current
        return Locale.Region.isoRegions.compactMap { region in
            guard region.isISORegion else { return nil }
            guard region.category == .territory else { return nil }

            let code = region.identifier.uppercased()
            guard code.count == 2 else { return nil }
            guard let name = locale.localizedString(forRegionCode: code) else { return nil }

            let continent = continent(for: region)
            return CountryEntry(name: name, code: code, continent: continent)
        }
        .reduce(into: [String: CountryEntry]()) { partialResult, entry in
            // Keep one entry per ISO code in case the locale produces duplicates.
            partialResult[entry.code] = entry
        }
        .map(\.value)
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    private static let localCitiesByCountryCode: [String: [LocalCityEntry]] = loadLocalCitiesByCountryCode()

    private var filteredCountryEntries: [CountryEntry] {
        let normalizedQuery = normalize(countryQuery)
        guard !normalizedQuery.isEmpty else { return Self.countryEntries }

        return Self.countryEntries.filter { normalize($0.name).contains(normalizedQuery) }
    }

    private var groupedCountryEntries: [(continent: Continent, entries: [CountryEntry])] {
        let grouped = Dictionary(grouping: filteredCountryEntries) { $0.continent }
        return Continent.orderedCases.compactMap { continent in
            guard let entries = grouped[continent], !entries.isEmpty else { return nil }
            return (continent: continent, entries: entries)
        }
    }

    private var canSave: Bool {
        selectedCountry != nil && selectedCity != nil && !isSaving
    }

    private var canContinue: Bool {
        selectedCountry != nil && selectedCity != nil
    }

    var body: some View {
        let baseContent = NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                if currentStep == .location {
                    locationStepListContent
                } else {
                    detailsStepScrollContent
                }
            }
            .navigationTitle(L10n.tr("Add Trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveTrip()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 19, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .appSymbolPulse(value: canSave && currentStep == .details)
                        }
                    }
                    .tint(.accentColor)
                    .disabled(!canSave || currentStep != .details)
                    .accessibilityLabel(L10n.tr("Save trip"))
                    .accessibilityHint(L10n.tr("Saves this trip with destination and details"))
                }
            }
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .onAppear {
                initializeTripDefaultsIfNeeded()
            }
            .onChange(of: selectedCountry) { _, country in
                resetCountrySelectionState()
                countryRegionTask?.cancel()

                guard let country else { return }
                fetchCitiesFromApple(initialLoad: true)
                countryRegionTask = Task {
                    await updateCountryRegion(for: country)
                    fetchCitiesFromApple(initialLoad: true)
                }
            }
            .onChange(of: cityQuery) { _, _ in
                guard selectedCountry != nil else { return }
                resetCitySelectionState()
                fetchCitiesFromApple(initialLoad: false)
            }
            .onDisappear {
                citySearchTask?.cancel()
                countryRegionTask?.cancel()
            }
            .animation(.easeInOut(duration: 0.2), value: currentStep)
        }

        if currentStep == .location {
            baseContent
                .searchable(text: activeSearchText, placement: .navigationBarDrawer(displayMode: .always), prompt: activeSearchPrompt)
        } else {
            baseContent
        }
    }

    private var activeSearchText: Binding<String> {
        selectedCountry == nil ? $countryQuery : $cityQuery
    }

    private var activeSearchPrompt: String {
        selectedCountry == nil ? L10n.tr("Filter countries") : L10n.tr("Filter cities")
    }

    private func intentSymbol(for intent: TravelIntent) -> String {
        switch intent {
        case .been:
            return "checkmark.seal.fill"
        case .wantToGo:
            return "airplane.departure"
        }
    }

    private var progressPercentage: Int {
        Int((progressValue * 100).rounded())
    }

    private var locationStepListContent: some View {
        List {
            Section {
                stepOverviewCard
                    .listRowCardStyle()

                travelIntentCard
                    .listRowCardStyle()
            }

            if selectedCountry == nil {
                if filteredCountryEntries.isEmpty {
                    Section {
                        ContentUnavailableView.search(text: countryQuery)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    ForEach(groupedCountryEntries, id: \.continent) { group in
                        Section(group.continent.label) {
                            ForEach(group.entries) { entry in
                                countryRow(entry)
                            }
                        }
                    }
                }
            } else {
                Section(L10n.tr("Selected Country")) {
                    selectedCountryListRow
                }

                Section(L10n.tr("Cities")) {
                    if isFetchingCities {
                        citiesLoadingSkeleton
                    } else if citySuggestions.isEmpty {
                        ContentUnavailableView.search(text: cityQuery)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(citySuggestions) { suggestion in
                            cityRow(suggestion)
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    ActionableErrorCard(
                        title: L10n.tr("Something went wrong"),
                        message: errorMessage,
                        retryAction: { retryAfterError() },
                        offlineAction: { workOfflineAfterError() },
                        supportAction: { contactSupport(errorMessage: errorMessage) }
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var detailsStepScrollContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                stepOverviewCard
                travelIntentCard
                detailsStepSections

                if let errorMessage {
                    ActionableErrorCard(
                        title: L10n.tr("Something went wrong"),
                        message: errorMessage,
                        retryAction: { retryAfterError() },
                        offlineAction: { workOfflineAfterError() },
                        supportAction: { contactSupport(errorMessage: errorMessage) }
                    )
                    .addTripCardSurface()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var detailsStepSections: some View {
        selectedCountrySection
        selectedCitySection
        tripDetailsSection
    }

    private var stepOverviewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .appSymbolPulse(value: progressPercentage)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(currentStep == .location ? L10n.tr("Trip setup") : L10n.tr("Final details"))
                        .font(.headline)
                    Text(currentStep == .location
                         ? L10n.tr("Choose country and city, then continue with travel details.")
                         : L10n.tr("Review details and save this trip to your timeline."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(L10n.f("%d%%", progressPercentage))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .appNumericTextTransition(Double(progressPercentage))
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: progressValue)
            }

            ProgressView(value: progressValue, total: 1)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .animation(.easeInOut(duration: 0.2), value: progressValue)
        }
        .addTripCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.tr("Trip setup progress"))
        .accessibilityValue(L10n.f("%lld percent complete", progressPercentage))
    }

    private var selectedCountryListRow: some View {
        LabeledContent {
            Button(L10n.tr("Change")) {
                selectedCountry = nil
                currentStep = .location
            }
            .buttonStyle(.borderless)
        } label: {
            HStack(spacing: 8) {
                Text(flagEmoji(for: selectedCountry ?? ""))
                Text(selectedCountry ?? "")
                    .fontWeight(.semibold)
            }
        }
    }

    private var progressValue: Double {
        if currentStep == .details { return 1 }
        if canContinue { return 0.7 }
        if selectedCountry != nil { return 0.45 }
        return 0.2
    }

    private var travelIntentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Trip type", subtitle: "Classify this destination for planning")

            Picker(L10n.tr("Trip type"), selection: $travelIntent) {
                ForEach(TravelIntent.allCases, id: \.self) { intent in
                    Text(intent.label).tag(intent)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Image(systemName: intentSymbol(for: travelIntent))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .appSymbolPulse(value: travelIntent)
                    .accessibilityHidden(true)
                Text(travelIntent == .been
                     ? L10n.tr("This trip already happened.")
                     : L10n.tr("This trip is a planned destination."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .addTripCardSurface()
    }

    private var selectedCountrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Country", subtitle: "Search and refine cities inside this country")

            LabeledContent {
                Button(L10n.tr("Change")) {
                    selectedCountry = nil
                    currentStep = .location
                }
                .buttonStyle(.borderless)
            } label: {
                HStack(spacing: 8) {
                    Text(flagEmoji(for: selectedCountry ?? ""))
                    Text(selectedCountry ?? "")
                        .fontWeight(.semibold)
                }
            }
        }
        .addTripCardSurface()
    }

    private var selectedCitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "Destination", subtitle: "Selected city for this trip")

            LabeledContent {
                Button(L10n.tr("Change")) {
                    currentStep = .location
                }
                .buttonStyle(.borderless)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCity?.name ?? "")
                        .fontWeight(.semibold)
                    Text(selectedCity?.country ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .addTripCardSurface()
    }

    private var tripDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Trip details", subtitle: "Timeline, transport and budget")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(L10n.tr("Schedule"), systemImage: "calendar")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(L10n.f("%lld nights", tripNights))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .appNumericTextTransition(Double(tripNights))
                        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: tripNights)
                }

                DatePicker(
                    L10n.tr("Departure"),
                    selection: $tripStartDate,
                    displayedComponents: .date
                )
                .onChange(of: tripStartDate) { _, newValue in
                    if tripEndDate < newValue {
                        tripEndDate = newValue
                    }
                }

                DatePicker(
                    L10n.tr("Return"),
                    selection: $tripEndDate,
                    in: tripStartDate...,
                    displayedComponents: .date
                )
            }
            .tripDetailInsetSurface()

            VStack(alignment: .leading, spacing: 10) {
                Label(L10n.tr("Transport"), systemImage: "airplane")
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(TransportType.allCases, id: \.self) { transportType in
                        transportOptionButton(transportType)
                    }
                }
            }
            .tripDetailInsetSurface()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(L10n.tr("Travelers"), systemImage: "person.2.fill")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(tripPeople)")
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                        .appNumericTextTransition(Double(tripPeople))
                        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: tripPeople)
                }

                HStack(spacing: 10) {
                    peopleButton(symbol: "minus", isEnabled: tripPeople > 1) {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            tripPeople = max(1, tripPeople - 1)
                        }
                    }

                    Capsule(style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                        .frame(height: 36)
                        .overlay(
                            Text(L10n.f("%lld travelers", tripPeople))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .appNumericTextTransition(Double(tripPeople))
                        )

                    peopleButton(symbol: "plus", isEnabled: tripPeople < 20) {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                            tripPeople = min(20, tripPeople + 1)
                        }
                    }
                }

                Divider()

                HStack {
                    Label(L10n.tr("Budget"), systemImage: "creditcard.fill")
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(tripBudgetLabel)
                        .font(.headline.weight(.semibold))
                        .monospacedDigit()
                        .appNumericTextTransition(tripBudget)
                        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: tripBudget)
                }

                Slider(value: $tripBudget, in: budgetSliderRange, step: 50)
                    .tint(.accentColor)

                TextField(L10n.tr("Custom amount"), value: $tripBudget, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Label(L10n.tr("Estimated CO2"), systemImage: "leaf.fill")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L10n.f("%lld kg", liveCo2Estimate))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .appNumericTextTransition(Double(liveCo2Estimate))
                        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: liveCo2Estimate)
                }
            }
            .tripDetailInsetSurface()
        }
        .addTripCardSurface()
    }

    private var tripNights: Int {
        max(1, Calendar.current.dateComponents([.day], from: tripStartDate, to: tripEndDate).day ?? 1)
    }

    private var budgetSliderRange: ClosedRange<Double> {
        let suggestedMax = homeViewModel.userProfile?.budgetMax ?? 4_000
        let upperBound = max(3_000.0, min(Double(suggestedMax) * 2, 30_000))
        return 0...upperBound
    }

    private var tripBudgetLabel: String {
        let currencyCode = Locale.current.currency?.identifier ?? "EUR"
        return tripBudget.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    private var liveCo2Estimate: Int {
        guard let selectedCity else { return 0 }
        let distanceKm = TravelDistanceCalculator.distanceKm(
            from: TravelDistanceCalculator.homeCoordinate(from: homeViewModel.userProfile),
            to: (selectedCity.latitude, selectedCity.longitude)
        )
        let estimate = bootstrap.co2Estimator.estimate(
            distanceKm: distanceKm,
            transportType: tripTransportType,
            people: max(1, tripPeople)
        )
        return Int(estimate.rounded())
    }

    private func transportOptionButton(_ transportType: TransportType) -> some View {
        let isSelected = tripTransportType == transportType

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                tripTransportType = transportType
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: transportType.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .appSymbolPulse(value: isSelected)

                Text(transportType.localizedTitle)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.35) : Color(uiColor: .separator).opacity(0.14),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
        .accessibilityLabel(L10n.f("%@ transport", transportType.localizedTitle))
        .accessibilityValue(isSelected ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(L10n.tr("Choose transport type for this trip"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func peopleButton(symbol: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.accentColor : .secondary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color(uiColor: .systemBackground))
                )
                .overlay(
                    Circle()
                        .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(symbol == "minus" ? L10n.tr("Decrease travelers") : L10n.tr("Increase travelers"))
        .accessibilityHint(L10n.tr("Adjust number of travelers"))
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.tr(title))
                .font(.headline)
            Text(L10n.tr(subtitle))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func countryRow(_ entry: CountryEntry) -> some View {
        let isSelected = selectedCountry == entry.name

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedCountry = entry.name
            }
        } label: {
            HStack(spacing: 10) {
                Text(flagEmoji(for: entry.name))
                Text(entry.name)
                    .fontWeight(.semibold)

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .appSymbolPulse(value: isSelected)
            }
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
        .foregroundStyle(.primary)
        .accessibilityLabel(L10n.f("Country %@", entry.name))
        .accessibilityValue(isSelected ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(L10n.tr("Select this country to load available cities"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cityCountryLabel(for suggestion: AppleCitySuggestion) -> String {
        if normalize(suggestion.country) == normalize(selectedCountry ?? "") {
            return suggestion.region ?? suggestion.country
        }
        return [suggestion.region, suggestion.country]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func cityRow(_ suggestion: AppleCitySuggestion) -> some View {
        let isSelected = selectedCity?.id == suggestion.id

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selectedCity = suggestion
                enterDetailsStep()
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.name)
                            .foregroundStyle(.primary)
                        Text(cityCountryLabel(for: suggestion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Text(flagEmoji(for: suggestion.country))
                }
                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .appSymbolPulse(value: isSelected)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(L10n.f("City %@, %@", suggestion.name, cityCountryLabel(for: suggestion)))
        .accessibilityValue(isSelected ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(L10n.tr("Select this city and continue to trip details"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var citiesLoadingSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonView()
                    .frame(height: 52)
            }
        }
        .padding(.vertical, 2)
    }

    private func retryAfterError() {
        if currentStep == .details {
            saveTrip()
        } else {
            fetchCitiesFromApple(initialLoad: false)
        }
    }

    private func workOfflineAfterError() {
        guard let selectedCountry else {
            errorMessage = nil
            return
        }

        let trimmedQuery = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if let localSuggestions = localCitySuggestions(
            selectedCountry: selectedCountry,
            trimmedQuery: trimmedQuery
        ) {
            citySuggestions = localSuggestions
            isFetchingCities = false
            errorMessage = L10n.tr("Offline mode enabled. Showing local city data.")
            return
        }

        errorMessage = L10n.tr("Offline mode enabled. No local city data found for this country.")
    }

    private func contactSupport(errorMessage: String) {
        let subject = "BeLocal trip setup support"
        let body = "Screen: Add trip\nError: \(errorMessage)"
        guard let url = SupportContact.emailURL(subject: subject, body: body) else { return }
        openURL(url)
    }

    private func fetchCitiesFromApple(initialLoad: Bool) {
        citySearchTask?.cancel()

        guard let selectedCountry else { return }

        citySearchTask = Task {
            if !initialLoad {
                try? await Task.sleep(nanoseconds: 280_000_000)
            }
            guard !Task.isCancelled else { return }

            await MainActor.run {
                isFetchingCities = true
                errorMessage = nil
            }

            let trimmedQuery = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if let localSuggestions = localCitySuggestions(
                selectedCountry: selectedCountry,
                trimmedQuery: trimmedQuery
            ) {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    citySuggestions = localSuggestions
                    isFetchingCities = false
                    errorMessage = nil
                }
                return
            }

            let queryCountry = countryEnglishName ?? selectedCountry
            let queries = citySearchQueries(
                trimmedQuery: trimmedQuery,
                queryCountry: queryCountry
            )

            do {
                let mapItems = try await runAppleSearchMapItems(
                    queries: queries,
                    requireAtLeastOneSuccess: !trimmedQuery.isEmpty
                )
                guard !Task.isCancelled else { return }

                let selectedCountryCode = countryCode(for: selectedCountry)
                var seen = Set<String>()

                let rawSuggestions = mapItems.compactMap { mapItem -> AppleCitySuggestion? in
                    citySuggestion(
                        from: mapItem,
                        selectedCountry: selectedCountry,
                        selectedCountryCode: selectedCountryCode,
                        seen: &seen,
                        enforceCountryMatch: true
                    )
                }
                let fallbackSuggestions: [AppleCitySuggestion]
                if rawSuggestions.isEmpty {
                    var fallbackSeen = Set<String>()
                    fallbackSuggestions = mapItems.compactMap { mapItem -> AppleCitySuggestion? in
                        citySuggestion(
                            from: mapItem,
                            selectedCountry: selectedCountry,
                            selectedCountryCode: selectedCountryCode,
                            seen: &fallbackSeen,
                            enforceCountryMatch: false
                        )
                    }
                } else {
                    fallbackSuggestions = rawSuggestions
                }
                let suggestions = fallbackSuggestions.sorted { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

                await MainActor.run {
                    citySuggestions = suggestions
                    isFetchingCities = false
                    errorMessage = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    citySuggestions = []
                    isFetchingCities = false
                    errorMessage = L10n.f("Unable to load cities from Apple Maps. %@", error.localizedDescription)
                }
            }
        }
    }

    private func localCitySuggestions(
        selectedCountry: String,
        trimmedQuery: String
    ) -> [AppleCitySuggestion]? {
        guard let selectedCountryCode = countryCode(for: selectedCountry) else { return nil }
        guard let localCities = Self.localCitiesByCountryCode[selectedCountryCode], !localCities.isEmpty else { return nil }

        let normalizedQuery = normalize(trimmedQuery)
        let filtered: [LocalCityEntry]
        if normalizedQuery.isEmpty {
            filtered = localCities
        } else {
            filtered = localCities.filter { city in
                let localized = normalize(city.name)
                let ascii = normalize(city.asciiName)
                return localized.contains(normalizedQuery) || ascii.contains(normalizedQuery)
            }
        }

        let ranked = filtered.sorted { lhs, rhs in
            if normalizedQuery.isEmpty {
                if lhs.population == rhs.population {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.population > rhs.population
            }

            let lhsPrefix = normalize(lhs.name).hasPrefix(normalizedQuery) || normalize(lhs.asciiName).hasPrefix(normalizedQuery)
            let rhsPrefix = normalize(rhs.name).hasPrefix(normalizedQuery) || normalize(rhs.asciiName).hasPrefix(normalizedQuery)
            if lhsPrefix != rhsPrefix {
                return lhsPrefix
            }
            if lhs.population == rhs.population {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.population > rhs.population
        }

        return ranked.map { city in
            AppleCitySuggestion(
                name: city.name,
                country: selectedCountry,
                region: nil,
                latitude: city.latitude,
                longitude: city.longitude
            )
        }
    }

    private func citySuggestion(
        from mapItem: MKMapItem,
        selectedCountry: String,
        selectedCountryCode: String?,
        seen: inout Set<String>,
        enforceCountryMatch: Bool
    ) -> AppleCitySuggestion? {
        let representations = mapItem.addressRepresentations
        let country = representations?.regionName ?? selectedCountry
        let city = representations?.cityName ?? mapItem.name

        guard let city, !city.isEmpty else { return nil }
        guard normalize(city) != normalize(selectedCountry) else { return nil }

        if enforceCountryMatch, let selectedCountryCode {
            let mapItemCountryCode = representations?.region?.identifier.uppercased() ?? countryCode(for: country)
            if let mapItemCountryCode, mapItemCountryCode != selectedCountryCode {
                return nil
            }
        }

        let key = "\(normalize(city))|\(normalize(country))"
        guard seen.insert(key).inserted else { return nil }

        let location = mapItem.location.coordinate
        return AppleCitySuggestion(
            name: city,
            country: country,
            region: representations?.cityWithContext,
            latitude: location.latitude,
            longitude: location.longitude
        )
    }

    private func citySearchQueries(trimmedQuery: String, queryCountry: String) -> [String] {
        if !trimmedQuery.isEmpty {
            return [
                "\(trimmedQuery), \(queryCountry)",
                "\(trimmedQuery) \(queryCountry)"
            ]
        }

        let discoveryQueries = [
            "cities in \(queryCountry)",
            "major cities in \(queryCountry)",
            "largest cities in \(queryCountry)",
            "towns in \(queryCountry)",
            "capitals in \(queryCountry)",
            "municipalities in \(queryCountry)"
        ]

        let letterQueries = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "L", "M", "N", "P", "R", "S", "T"]
            .map { "\($0), \(queryCountry)" }

        return (discoveryQueries + letterQueries).removingDuplicates()
    }

    private func runAppleSearchMapItems(
        queries: [String],
        requireAtLeastOneSuccess: Bool
    ) async throws -> [MKMapItem] {
        var merged: [MKMapItem] = []
        var lastError: Error?
        var hasAtLeastOneSuccess = false

        for query in queries {
            guard !Task.isCancelled else { break }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .address
            if let countrySearchRegion {
                request.region = countrySearchRegion
            }
            do {
                let response = try await MKLocalSearch(request: request).start()
                merged.append(contentsOf: response.mapItems)
                hasAtLeastOneSuccess = true
            } catch {
                lastError = error
                continue
            }
        }

        if requireAtLeastOneSuccess && !hasAtLeastOneSuccess {
            throw lastError ?? NSError(domain: "AppleSearch", code: -1, userInfo: [NSLocalizedDescriptionKey: L10n.tr("Apple Maps city search failed.")])
        }

        return merged
    }

    private func saveTrip() {
        guard let profile = homeViewModel.userProfile else {
            errorMessage = L10n.tr("Missing user profile. Open Settings first.")
            return
        }
        guard let selectedCity else {
            errorMessage = L10n.tr("Choose a city first.")
            return
        }

        isSaving = true
        errorMessage = nil

        let destination = resolveDestination(from: selectedCity)

        if !homeViewModel.destinations.contains(where: { $0.id == destination.id }) {
            modelContext.insert(destination)
        }

        let startDate = tripStartDate
        let endDate = max(tripEndDate, startDate)
        let people = max(tripPeople, 1)
        let budget = max(tripBudget, 0)
        let co2 = bootstrap.co2Estimator.estimate(
            distanceKm: destination.distanceKm,
            transportType: tripTransportType,
            people: people
        )

        let trip = Trip(
            userId: profile.id,
            destinationId: destination.id,
            startDate: startDate,
            endDate: endDate,
            transportType: tripTransportType,
            tripIntent: travelIntent == .been ? .been : .wantToGo,
            people: people,
            budgetSpent: budget,
            co2Estimated: co2,
            ecoScoreSnapshot: destination.ecoScore
        )

        modelContext.insert(trip)

        bootstrap.syncManager.enqueue(
            type: .createTrip,
            payload: [
                "tripId": trip.id.uuidString,
                "userId": trip.userId.uuidString,
                "destinationId": destination.id.uuidString,
                "budgetSpent": String(format: "%.0f", trip.budgetSpent),
                "startDate": ISO8601DateFormatter().string(from: trip.startDate),
                "endDate": ISO8601DateFormatter().string(from: trip.endDate),
                "transportType": trip.transportType.rawValue,
                "people": "\(trip.people)",
                "co2Estimated": String(format: "%.2f", trip.co2Estimated),
                "ecoScoreSnapshot": String(format: "%.4f", trip.ecoScoreSnapshot),
                "destinationName": destination.name,
                "destinationCountry": destination.country,
                "destinationLatitude": String(format: "%.6f", destination.latitude),
                "destinationLongitude": String(format: "%.6f", destination.longitude),
                "destinationDistanceKm": String(format: "%.3f", destination.distanceKm),
                "destinationEcoScore": String(format: "%.3f", destination.ecoScore),
                "destinationClimate": destination.climate,
                "destinationCostIndex": String(format: "%.3f", destination.costIndex),
                "destinationCrowdingIndex": String(format: "%.3f", destination.crowdingIndex),
                "destinationStylesJSON": CodableStorage.encode(destination.styles, fallback: "[]"),
                "destinationTypicalSeasonJSON": CodableStorage.encode(destination.typicalSeason, fallback: "[]"),
                "intent": travelIntent.rawValue,
                "source": "apple_maps"
            ],
            context: modelContext
        )

        do {
            try modelContext.save()
            homeViewModel.load(
                context: modelContext,
                bootstrap: bootstrap,
                preferOffline: homeViewModel.isOfflineModeEnabled
            )
            homeViewModel.refreshRecommendations(bootstrap: bootstrap)
            onSaved()
            dismiss()
        } catch {
            errorMessage = L10n.tr("Failed to save trip.")
            isSaving = false
        }
    }

    private func resolveDestination(from suggestion: AppleCitySuggestion) -> Destination {
        let distanceKm = TravelDistanceCalculator.distanceKm(
            from: TravelDistanceCalculator.homeCoordinate(from: homeViewModel.userProfile),
            to: (suggestion.latitude, suggestion.longitude)
        )

        if let existing = homeViewModel.destinations.first(where: {
            normalize($0.name) == normalize(suggestion.name) &&
            normalize($0.country) == normalize(suggestion.country)
        }) {
            existing.distanceKm = distanceKm
            existing.styles = DestinationMetadataInferer.sanitizeStyles(existing.styles)
            existing.crowdingIndex = DestinationMetadataInferer.normalizeCrowding(existing.crowdingIndex)
            existing.costIndex = DestinationMetadataInferer.normalizeCostIndex(existing.costIndex)
            existing.typicalSeason = DestinationMetadataInferer.sanitizeSeason(
                existing.typicalSeason,
                climate: existing.climate,
                latitude: existing.latitude
            )
            return existing
        }

        let inferred = DestinationMetadataInferer.infer(
            name: suggestion.name,
            country: suggestion.country,
            latitude: suggestion.latitude,
            longitude: suggestion.longitude,
            population: inferredPopulation(for: suggestion),
            featureCode: nil,
            distanceKm: distanceKm
        )

        return Destination(
            name: suggestion.name,
            country: suggestion.country,
            latitude: suggestion.latitude,
            longitude: suggestion.longitude,
            styles: inferred.styles,
            climate: inferred.climate,
            costIndex: inferred.costIndex,
            ecoScore: inferred.ecoScore,
            crowdingIndex: inferred.crowdingIndex,
            typicalSeason: inferred.typicalSeason,
            distanceKm: distanceKm
        )
    }

    private func inferredPopulation(for suggestion: AppleCitySuggestion) -> Int? {
        guard let code = countryCode(for: suggestion.country),
              let localEntries = Self.localCitiesByCountryCode[code] else {
            return nil
        }

        let normalizedName = normalize(suggestion.name)
        let closest = localEntries
            .filter {
                normalize($0.name) == normalizedName || normalize($0.asciiName) == normalizedName
            }
            .sorted { lhs, rhs in
                let lhsDistance = TravelDistanceCalculator.distanceKm(
                    from: (lhs.latitude, lhs.longitude),
                    to: (suggestion.latitude, suggestion.longitude)
                )
                let rhsDistance = TravelDistanceCalculator.distanceKm(
                    from: (rhs.latitude, rhs.longitude),
                    to: (suggestion.latitude, suggestion.longitude)
                )
                if lhsDistance == rhsDistance {
                    return lhs.population > rhs.population
                }
                return lhsDistance < rhsDistance
            }
            .first

        return closest?.population
    }

    private func flagEmoji(for country: String) -> String {
        for code in Locale.Region.isoRegions.map(\.identifier) {
            guard let localized = Locale.current.localizedString(forRegionCode: code) else { continue }
            if normalize(localized) == normalize(country) {
                let base: UInt32 = 127397
                let scalars = code.uppercased().unicodeScalars.compactMap { scalar in
                    UnicodeScalar(base + scalar.value)
                }
                return String(String.UnicodeScalarView(scalars))
            }
        }

        return "🏳️"
    }

    private func normalize(_ value: String) -> String {
        PlaceCanonicalizer.normalizeText(value)
    }

    private static func continent(for region: Locale.Region) -> Continent {
        let subcontinentCode = region.subcontinent?.identifier
        if subcontinentCode == "021" || subcontinentCode == "013" || subcontinentCode == "029" {
            return .northAmerica
        }
        if subcontinentCode == "005" {
            return .southAmerica
        }

        switch region.continent?.identifier {
        case "002":
            return .africa
        case "142":
            return .asia
        case "150":
            return .europe
        case "009":
            return .oceania
        case "010":
            return .antarctica
        default:
            return .other
        }
    }

    private static func loadLocalCitiesByCountryCode() -> [String: [LocalCityEntry]] {
        CityDataset.populatedPlacesByCountryCode.mapValues { entries in
            entries.compactMap { entry in
                let countryCode = entry.countryCode
                guard countryCode.count == 2 else { return nil }

                let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                return LocalCityEntry(
                    name: name,
                    asciiName: entry.asciiName,
                    countryCode: countryCode,
                    latitude: entry.latitude,
                    longitude: entry.longitude,
                    population: entry.population
                )
            }
        }
    }

    private func countryCode(for countryName: String) -> String? {
        for code in Locale.Region.isoRegions.map(\.identifier) {
            guard let localized = Locale.current.localizedString(forRegionCode: code) else { continue }
            if normalize(localized) == normalize(countryName) {
                return code.uppercased()
            }
        }
        return nil
    }

    private func englishCountryName(for countryName: String) -> String? {
        let englishLocale = Locale(identifier: "en_US_POSIX")
        for code in Locale.Region.isoRegions.map(\.identifier) {
            guard let localized = Locale.current.localizedString(forRegionCode: code) else { continue }
            if normalize(localized) == normalize(countryName) {
                return englishLocale.localizedString(forRegionCode: code)
            }
        }
        return nil
    }

    private func updateCountryRegion(for countryName: String) async {
        let englishName = englishCountryName(for: countryName)
        await MainActor.run {
            countryEnglishName = englishName
        }
        let query = englishName ?? countryName

        do {
            guard let request = MKGeocodingRequest(addressString: query) else {
                await MainActor.run {
                    countrySearchRegion = nil
                }
                return
            }

            let mapItems = try await geocodedMapItems(for: request)
            guard let location = mapItems.first?.location else {
                await MainActor.run {
                    countrySearchRegion = nil
                }
                return
            }

            let span = MKCoordinateSpan(latitudeDelta: 14, longitudeDelta: 14)
            let region = MKCoordinateRegion(center: location.coordinate, span: span)

            await MainActor.run {
                countrySearchRegion = region
            }
        } catch {
            await MainActor.run {
                countrySearchRegion = nil
            }
        }
    }

    private func geocodedMapItems(for request: MKGeocodingRequest) async throws -> [MKMapItem] {
        try await withCheckedThrowingContinuation { continuation in
            request.getMapItems { mapItems, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: mapItems ?? [])
                }
            }
        }
    }

    private func initializeTripDefaultsIfNeeded() {
        guard !didInitializeTripDefaults else { return }
        didInitializeTripDefaults = true

        if let profile = homeViewModel.userProfile {
            tripPeople = max(profile.peopleDefault, 1)
            tripBudget = max(profile.budgetMin, 0)
        }
    }

    private func resetCountrySelectionState() {
        selectedCity = nil
        cityQuery = ""
        citySuggestions = []
        errorMessage = nil
        countrySearchRegion = nil
        countryEnglishName = nil
        currentStep = .location
    }

    private func resetCitySelectionState() {
        selectedCity = nil
        currentStep = .location
    }

    private func enterDetailsStep() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            currentStep = .details
        }
    }

}

private extension View {
    func listRowCardStyle() -> some View {
        self
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    @ViewBuilder
    func appNumericTextTransition(_ value: Double) -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.numericText(value: value))
        } else {
            self
        }
    }

    @ViewBuilder
    func appSymbolPulse<Value: Equatable>(value: Value) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.pulse, value: value)
        } else {
            self
        }
    }

    func addTripCardSurface() -> some View {
        self
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
            )
    }

    func tripDetailInsetSurface() -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
            )
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.addtrip") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext
    bootstrap.prepare(context: context)

    let homeViewModel = HomeViewModel()
    homeViewModel.load(context: context, bootstrap: bootstrap)

    return AddTripSheetView(homeViewModel: homeViewModel) {}
        .environment(bootstrap)
        .modelContainer(container)
}
