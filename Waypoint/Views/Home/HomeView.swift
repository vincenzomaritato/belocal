import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var homeViewModel: HomeViewModel
    var onPlannerSuggestionTap: ((RecommendationItem) -> Void)? = nil
    var onProfileTap: (() -> Void)? = nil

    @State private var selectedStyleFilter = "All"
    @State private var feedbackViewModel: TripDetailViewModel?
    @State private var showNoTripsAlert = false
    @State private var showAddTripSheet = false

    private var feedbackLocationOptions: [FeedbackLocationOption] {
        let now = Date()
        let sourceTrips = homeViewModel.trips.contains(where: { $0.endDate <= now })
            ? homeViewModel.trips.filter { $0.endDate <= now }
            : homeViewModel.trips

        return sourceTrips
            .sorted { $0.endDate > $1.endDate }
            .compactMap { trip in
                guard let destination = homeViewModel.destination(for: trip) else { return nil }
                let sourceType = FeedbackAudienceResolver.sourceType(
                    userProfile: homeViewModel.userProfile,
                    destinationName: destination.name,
                    destinationCountry: destination.country,
                    destinationCoordinate: (latitude: destination.latitude, longitude: destination.longitude)
                )
                return FeedbackLocationOption(
                    tripId: trip.id,
                    destinationId: destination.id,
                    destinationName: destination.name,
                    country: destination.country,
                    destinationLatitude: destination.latitude,
                    destinationLongitude: destination.longitude,
                    sourceType: sourceType,
                    authorHomeCity: homeViewModel.userProfile?.homeCity ?? "",
                    authorHomeCountry: homeViewModel.userProfile?.homeCountry ?? "",
                    periodLabel: tripPeriodLabel(for: trip)
                )
            }
    }

    private var availableStyleFilters: [String] {
        let totalRecommendations = max(homeViewModel.recommendations.count, 1)
        let minimumCount = totalRecommendations >= 5 ? 2 : 1

        let rawCounts = homeViewModel.recommendations
            .reduce(into: [String: Int]()) { counts, item in
                let uniqueStyles = Set(
                    item.destination.styles
                        .map(PlaceCanonicalizer.canonicalStyle)
                        .map(styleKey(for:))
                )
                for style in uniqueStyles {
                    counts[style, default: 0] += 1
                }
            }

        let dynamicStyles = rawCounts
            .filter { _, count in
                let coverage = Double(count) / Double(totalRecommendations)
                return count >= minimumCount && coverage < 0.85
            }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map { displayStyle(from: $0.key) }

        let fallbackStyles = rawCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map { displayStyle(from: $0.key) }

        var topStyles = Array((dynamicStyles.isEmpty ? fallbackStyles : dynamicStyles).prefix(6))

        if topStyles.count <= 1 {
            let profileStyles = (homeViewModel.userProfile?.travelStyleWeights ?? [:])
                .sorted { $0.value > $1.value }
                .map(\.key)
            let merged = Array(NSOrderedSet(array: topStyles + profileStyles).compactMap { $0 as? String })
            topStyles = Array(merged.prefix(6))
        }

        return ["All"] + topStyles.filter { !$0.isEmpty && $0 != "All" }
    }

    private var filteredRecommendations: [RecommendationItem] {
        guard selectedStyleFilter != "All" else { return homeViewModel.recommendations }
        let selectedKey = styleKey(for: selectedStyleFilter)
        return homeViewModel.recommendations.filter { item in
            item.destination.styles
                .map(PlaceCanonicalizer.canonicalStyle)
                .map(styleKey(for:))
                .contains(selectedKey)
        }
    }

    private var navigationTitleText: String {
        let firstName = homeViewModel.userProfile?.name.split(separator: " ").first.map(String.init)
        if let firstName, !firstName.isEmpty {
            return "Welcome, \(firstName)"
        }
        return "Welcome"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                homeBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if homeViewModel.isOfflineModeEnabled {
                            offlineModeNotice
                        }

                        if homeViewModel.isLoading {
                            mapSectionSkeleton
                        } else {
                            mapSection
                        }

                        tripsSection

                        recommendationsSection
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 26)
                }
            }
            .navigationTitle(navigationTitleText)
            .toolbarTitleDisplayMode(.large)
            .toolbar {
                if let onProfileTap {
                    ToolbarItem(placement: .topBarLeading) {
                        ProfileToolbarButton(action: onProfileTap)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddTripSheet = true
                        } label: {
                            Label("Add Trip", systemImage: "airplane")
                        }

                        Button {
                            startFeedbackFlow()
                        } label: {
                            Label("Leave Feedback", systemImage: "star.bubble")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                    }
                    .tint(.orange)
                    .accessibilityLabel("Quick actions")
                    .accessibilityHint("Open actions to add a trip or leave feedback")
                }
            }
            .refreshable {
                reloadHome()
                if !homeViewModel.isOfflineModeEnabled {
                    await bootstrap.syncManager.processPendingOperations(context: modelContext)
                }
            }
            .onChange(of: availableStyleFilters) { _, newFilters in
                guard !newFilters.contains(selectedStyleFilter) else { return }
                selectedStyleFilter = "All"
            }
            .sheet(isPresented: feedbackSheetBinding) {
                if let viewModel = feedbackViewModel {
                    FeedbackFormView(viewModel: viewModel, locationOptions: feedbackLocationOptions) { selectedLocation in
                        viewModel.saveFeedback(
                            context: modelContext,
                            syncManager: bootstrap.syncManager,
                            selectedLocation: selectedLocation
                        ) {
                            reloadHome()
                        }
                    }
                    .presentationDetents([.large])
                }
            }
            .sheet(isPresented: $showAddTripSheet) {
                AddTripSheetView(homeViewModel: homeViewModel) {
                    reloadHome()
                    Task {
                        if !homeViewModel.isOfflineModeEnabled {
                            await bootstrap.syncManager.processPendingOperations(context: modelContext)
                        }
                    }
                }
                .presentationDetents([.large])
            }
            .alert("No Trips Yet", isPresented: $showNoTripsAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Add a trip first to leave feedback.")
            }
        }
    }

    private var homeBackground: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemGroupedBackground),
                Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 60)
                .offset(x: 90, y: -80)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 64)
                .offset(x: -80, y: 120)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var offlineModeNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .foregroundStyle(.indigo)
            Text("Offline mode is on. You can keep browsing and save changes locally.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Go Online") {
                reloadHome(forceOffline: false)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.indigo.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var mapSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Visited Footprint")
                        .font(.headline)
                    Spacer()
                    Text("\(homeViewModel.visitedCountryCodes.count) countries")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                StaticWorldMapView(countryCodes: homeViewModel.visitedCountryCodes)
                    .frame(height: 245)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Visited countries map")
                    .accessibilityValue("\(homeViewModel.visitedCountryCodes.count) countries visited")

                if homeViewModel.visitedCountryCodes.isEmpty {
                    Text("Start saving trips to color your world map.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Add your first trip") {
                        showAddTripSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var mapSectionSkeleton: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SkeletonView()
                    .frame(height: 18)
                SkeletonView()
                    .frame(height: 245)
                SkeletonView()
                    .frame(height: 16)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
    }

    private var tripsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Trips")
                .font(.title3.weight(.semibold))
                .padding(.leading, 2)

            if homeViewModel.isLoading {
                tripsRowSkeleton
            } else if homeViewModel.trips.isEmpty {
                EmptyStateCard(
                    icon: "airplane.circle",
                    title: "No trips yet",
                    message: "Add your first trip to unlock tailored recommendations and a richer world map.",
                    primaryActionTitle: "Add Trip",
                    primaryAction: { showAddTripSheet = true }
                )
            } else {
                recentTripsRow
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recommended for You")
                .font(.title3.weight(.semibold))
                .padding(.leading, 2)

            if availableStyleFilters.count > 1 {
                styleFilterRow
            }

            recommendationsContent
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var recentTripsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(homeViewModel.trips.prefix(8)), id: \.id) { trip in
                    NavigationLink {
                        TripDetailView(
                            viewModel: TripDetailViewModel(
                                trip: trip,
                                destination: homeViewModel.destination(for: trip)
                            ),
                            homeViewModel: homeViewModel
                        )
                    } label: {
                        TripCardView(trip: trip, destination: homeViewModel.destination(for: trip))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    private var tripsRowSkeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonView()
                        .frame(width: 268, height: 170)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var recommendationsContent: some View {
        if let errorMessage = homeViewModel.errorMessage {
            ActionableErrorCard(
                title: "Something went wrong",
                message: errorMessage,
                retryAction: { reloadHome() },
                offlineAction: { enterOfflineMode() },
                supportAction: { contactSupport(context: "home-load") }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else if homeViewModel.isLoading || (homeViewModel.isRefreshingRecommendations && homeViewModel.recommendations.isEmpty) {
            ForEach(0..<3, id: \.self) { _ in
                SkeletonView().frame(height: 130)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else if homeViewModel.recommendations.isEmpty {
            recommendationsEmptyState
        } else if filteredRecommendations.isEmpty {
            filteredEmptyState
        } else {
            ForEach(filteredRecommendations, id: \.id) { item in
                if let onPlannerSuggestionTap {
                    Button {
                        onPlannerSuggestionTap(item)
                    } label: {
                        DestinationCardView(item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        DestinationDetailView(
                            destination: item.destination,
                            recommendation: item,
                            localInsight: homeViewModel.localInsight(for: item.destination),
                            ecoAlternatives: homeViewModel.ecoAlternatives(for: item.destination),
                            travelerFeedback: homeViewModel.travelerFeedback.filter { feedback in
                                if let destinationId = feedback.destinationId {
                                    return destinationId == item.destination.id
                                }
                                return homeViewModel.trips.first(where: { $0.id == feedback.tripId })?.destinationId == item.destination.id
                            }
                        )
                    } label: {
                        DestinationCardView(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recommendationsEmptyState: some View {
        EmptyStateCard(
            icon: "sparkles",
            title: "No recommendations yet",
            message: homeViewModel.trips.isEmpty
                ? "Add your first trip and we will build suggestions around your profile."
                : "We need more destination signals to build your next set of ideas.",
            primaryActionTitle: "Add Trip",
            primaryAction: { showAddTripSheet = true },
            secondaryActionTitle: "Refresh",
            secondaryAction: { reloadHome() }
        )
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var filteredEmptyState: some View {
        EmptyStateCard(
            icon: "line.3.horizontal.decrease.circle",
            title: "No matches for \(selectedStyleFilter)",
            message: "Try another style filter to see more destinations.",
            primaryActionTitle: "Reset Filter",
            primaryAction: { selectedStyleFilter = "All" }
        )
        .padding(.vertical, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var styleFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableStyleFilters, id: \.self) { style in
                    filterChip(style)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ style: String) -> some View {
        let isSelected = selectedStyleFilter == style

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedStyleFilter = style
            }
        } label: {
            Text(style)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor
                                : Color(uiColor: .tertiarySystemGroupedBackground)
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected
                                ? Color.accentColor.opacity(0.35)
                                : Color(uiColor: .separator).opacity(0.18),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(style)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Currently selected" : "Double-tap to apply this filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var feedbackSheetBinding: Binding<Bool> {
        Binding(
            get: { feedbackViewModel?.showFeedbackSheet ?? false },
            set: { newValue in
                guard let viewModel = feedbackViewModel else { return }
                viewModel.showFeedbackSheet = newValue
                if !newValue {
                    feedbackViewModel = nil
                }
            }
        )
    }

    private func startFeedbackFlow() {
        guard let trip = homeViewModel.trips.first else {
            showNoTripsAlert = true
            return
        }

        let viewModel = TripDetailViewModel(
            trip: trip,
            destination: homeViewModel.destination(for: trip)
        )
        viewModel.feedbackDraft.selectedTripId = nil
        viewModel.showFeedbackSheet = true
        feedbackViewModel = viewModel
    }

    private func tripPeriodLabel(for trip: Trip) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: trip.startDate, to: trip.endDate)
    }

    private func reloadHome(forceOffline: Bool? = nil) {
        let shouldPreferOffline = forceOffline ?? homeViewModel.isOfflineModeEnabled
        homeViewModel.load(
            context: modelContext,
            bootstrap: bootstrap,
            preferOffline: shouldPreferOffline
        )
    }

    private func enterOfflineMode() {
        reloadHome(forceOffline: true)
    }

    private func contactSupport(context: String) {
        let subject = "Waypoint support request"
        let message = "Context: \(context)\nError: \(homeViewModel.errorMessage ?? "n/a")"
        guard let url = SupportContact.emailURL(subject: subject, body: message) else { return }
        openURL(url)
    }

    private func styleKey(for value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }

    private func displayStyle(from key: String) -> String {
        key
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if lower == "urban" { return "Urban" }
                if lower == "food" { return "Food" }
                if lower == "beach" { return "Beach" }
                if lower == "nature" { return "Nature" }
                if lower == "culture" { return "Culture" }
                return lower.capitalized
            }
            .joined(separator: " ")
    }

}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.homeview") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext
    bootstrap.prepare(context: context)

    let homeViewModel = HomeViewModel()
    homeViewModel.load(context: context, bootstrap: bootstrap)

    return HomeView(homeViewModel: homeViewModel)
        .environment(bootstrap)
        .modelContainer(container)
}
