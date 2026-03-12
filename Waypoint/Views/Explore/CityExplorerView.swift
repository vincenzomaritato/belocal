import MapKit
import SwiftData
import SwiftUI

private enum ExplorerSectionTab: String, CaseIterable, Identifiable {
    case forYou
    case attractions
    case feedback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: return L10n.tr("For You")
        case .feedback: return L10n.tr("Feedback")
        case .attractions: return L10n.tr("Attractions")
        }
    }

    var symbol: String {
        switch self {
        case .forYou: return "sparkles"
        case .feedback: return "star.bubble"
        case .attractions: return "building.columns"
        }
    }
}

private struct GlassSurface<S: Shape>: View {
    let shape: S
    let fallbackMaterial: Material

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect()
            } else {
                shape.fill(fallbackMaterial)
            }
        }
    }
}

struct CityExplorerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var homeViewModel: HomeViewModel
    @Bindable var viewModel: CityExplorerViewModel
    var onProfileTap: (() -> Void)? = nil

    @State private var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 10),
            span: MKCoordinateSpan(latitudeDelta: 115, longitudeDelta: 115)
        )
    )
    @State private var runningTask: Task<Void, Never>?
    @State private var isPanelPresented = true
    @State private var selectedDetent: PresentationDetent = .fraction(0.42)
    @State private var selectedTab: ExplorerSectionTab = .forYou
    @State private var translatedFeedbackByID: [UUID: FeedbackTranslationContent] = [:]

    private var placeLimit: Int {
        if selectedDetent == .large { return 10 }
        if selectedDetent == .fraction(0.62) { return 6 }
        return 3
    }

    private var infoLineLimit: Int {
        if selectedDetent == .large { return 12 }
        if selectedDetent == .fraction(0.62) { return 8 }
        return 4
    }

    private var isLoadingAnyData: Bool {
        viewModel.isResolvingLocation || viewModel.isLoadingInfo || viewModel.isLoadingPlaces || viewModel.isGeneratingBrief
    }

    private var averageRating: Double {
        let travelerEntries = viewModel.feedbackEntries.filter { $0.sourceType == .traveler }
        guard !travelerEntries.isEmpty else { return 0 }
        return Double(travelerEntries.map(\.rating).reduce(0, +)) / Double(travelerEntries.count)
    }

    private var localAverageRating: Double {
        let localEntries = viewModel.feedbackEntries.filter { $0.sourceType == .local }
        guard !localEntries.isEmpty else { return 0 }
        return Double(localEntries.map(\.rating).reduce(0, +)) / Double(localEntries.count)
    }

    private var topFeedbackTags: [String] {
        let tags = viewModel.feedbackEntries.flatMap { entry in
            translatedFeedbackByID[entry.id]?.tags ?? entry.tags
        }
        let counts = Dictionary(tags.map { ($0, 1) }, uniquingKeysWith: +)
        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .prefix(6)
            .map(\.key)
    }

    private var mapAccessibilityLabel: String {
        if let city = viewModel.selectedCity {
            return L10n.f("City map centered on %@", city.name)
        }
        return L10n.tr("City map")
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $mapPosition, interactionModes: .all) {
                if let selectedCity = viewModel.selectedCity {
                    Annotation(selectedCity.name, coordinate: selectedCity.coordinate, anchor: .center) {
                        selectedCityMarker
                    }
                }
            }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .ignoresSafeArea()
                .accessibilityLabel(mapAccessibilityLabel)
                .accessibilityHint(L10n.tr("Use gestures to explore the map and tap to select a city"))
                .simultaneousGesture(mapTapGesture(proxy: proxy))
                .overlay(alignment: .top) {
                    topMapChrome
                }
                .overlay(alignment: .bottomTrailing) {
                    if let selectedCity = viewModel.selectedCity {
                        recenterButton(for: selectedCity)
                            .padding(.trailing, 14)
                            .padding(.bottom, 14)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if !isPanelPresented {
                        showPanelButton
                            .padding(.leading, 14)
                            .padding(.bottom, 14)
                    }
                }
        }
        .sheet(isPresented: $isPanelPresented) {
            explorerPanel
                .presentationDetents([.fraction(0.42), .fraction(0.62), .large], selection: $selectedDetent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
                .presentationBackgroundInteraction(.enabled(upThrough: .large))
        }
        .onAppear {
            if !isPanelPresented {
                isPanelPresented = true
            }
            Task {
                await refreshExploreDataIfNeeded()
                viewModel.refreshLocalMatches(homeViewModel: homeViewModel)
            }
        }
        .onDisappear {
            runningTask?.cancel()
        }
        .task(id: homeViewModel.exploreDataVersion) {
            guard viewModel.selectedCity != nil else { return }
            viewModel.refreshLocalMatches(homeViewModel: homeViewModel)
        }
        .task(id: feedbackTranslationTaskID) {
            await refreshFeedbackTranslations()
        }
    }

    private var feedbackTranslationTaskID: String {
        let payload = viewModel.feedbackEntries.map { entry in
            "\(entry.id.uuidString)|\(entry.text)|\(entry.tags.joined(separator: "||"))"
        }
        .joined(separator: ":::")
        return "\(L10n.preferredLanguageCode)|\(payload)"
    }

    private var selectedCityMarker: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(width: 58, height: 58)
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(0.28), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)

            if let imageURL = viewModel.wikiInfo?.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        ProgressView()
                    case .failure:
                        markerFallbackGlyph
                    @unknown default:
                        markerFallbackGlyph
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                markerFallbackGlyph
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            }
        }
    }

    private var markerFallbackGlyph: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.20))
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private var topMapChrome: some View {
        VStack(spacing: 10) {
            HStack {
                if let onProfileTap {
                    ProfileToolbarButton(action: onProfileTap)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("Explore"))
                        .font(.title3.weight(.semibold))
                    Text(L10n.tr("Tap map or search a city"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isLoadingAnyData {
                    Label(L10n.tr("Updating"), systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            GlassSurface(
                                shape: Capsule(style: .continuous),
                                fallbackMaterial: .regularMaterial
                            )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
                        )
                        .appSymbolPulse(value: isLoadingAnyData)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                GlassSurface(
                    shape: RoundedRectangle(cornerRadius: 20, style: .continuous),
                    fallbackMaterial: .thinMaterial
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var explorerPanel: some View {
        VStack(spacing: 12) {
            panelHeader
            searchRow
            tabsRow

            ScrollView(.vertical, showsIndicators: selectedDetent == .large) {
                LazyVStack(spacing: 12) {
                    if let selectedCity = viewModel.selectedCity {
                        contentForSelectedTab(city: selectedCity)
                    } else {
                        emptyStateCard
                    }

                    if let statusMessage = viewModel.statusMessage {
                        statusMessageCard(statusMessage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scrollDisabled(selectedDetent == .fraction(0.42))
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaPadding(.top, 8)
        .safeAreaPadding(.horizontal, 16)
        .safeAreaPadding(.bottom, 4)
        .background(
            LinearGradient(
                colors: [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var panelHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.selectedCity?.name ?? L10n.tr("City Explorer"))
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                Text(viewModel.selectedCity?.label ?? L10n.tr("Search a city or long press on map."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Button {
                isPanelPresented = false
            } label: {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityTapTarget()
            .accessibilityLabel(L10n.tr("Hide panel"))
            .accessibilityHint(L10n.tr("Collapses city details and returns focus to the map"))
        }
        .padding(.top)
        .padding(.horizontal, 5)
    }

    private var showPanelButton: some View {
        Button {
            selectedDetent = .fraction(0.42)
            isPanelPresented = true
        } label: {
                Label(L10n.tr("Show details"), systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    GlassSurface(
                        shape: Capsule(style: .continuous),
                        fallbackMaterial: .regularMaterial
                    )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
        .accessibilityHint(L10n.tr("Shows city details and recommendations"))
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(L10n.tr("Search city (Lisbon, Tokyo, New York)"), text: $viewModel.searchText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchCity() }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .accessibilityLabel(L10n.tr("Clear search text"))
            }

            Button {
                searchCity()
            } label: {
                Image(systemName: "arrow.forward.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .accessibilityTapTarget()
            .disabled(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isResolvingLocation)
            .accessibilityLabel(L10n.tr("Search city"))
            .accessibilityHint(L10n.tr("Loads city details on the map"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
        )
    }

    private var tabsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ExplorerSectionTab.allCases) { tab in
                    tabChip(tab)
                }
            }
        }
    }

    private func tabChip(_ tab: ExplorerSectionTab) -> some View {
        let selected = selectedTab == tab
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                    .font(.caption.weight(.semibold))
                    .appSymbolPulse(value: selected)
                Text(tab.title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        selected ? Color.accentColor.opacity(0.25) : Color(uiColor: .separator).opacity(0.2),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
        .accessibilityLabel(L10n.f("Show %@ section", tab.title))
        .accessibilityValue(selected ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(L10n.tr("Switch explorer content tab"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func contentForSelectedTab(city: ExplorerCity) -> some View {
        switch selectedTab {
        case .forYou:
            forYouSection(city: city)
        case .attractions:
            placesSection(
                title: "Attractions",
                symbol: "building.columns",
                places: viewModel.attractions,
                emptyMessage: "No attractions available yet."
            )
        case .feedback:
            feedbackSection
        }
    }

    private func forYouSection(city: ExplorerCity) -> some View {
        VStack(spacing: 12) {
            sectionContainer(title: L10n.tr("City Snapshot"), symbol: "globe.europe.africa.fill") {
                citySnapshotCard(city: city)
            }

            sectionContainer(title: L10n.tr("Personalized Brief"), symbol: "sparkles") {
                if viewModel.isGeneratingBrief {
                    ProgressView(L10n.tr("Generating personalized summary..."))
                } else if let brief = viewModel.personalizedBrief, !brief.isEmpty {
                    Text(brief)
                        .font(.subheadline)
                } else {
                    Text(L10n.tr("No personalized brief available yet."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func citySnapshotCard(city: ExplorerCity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heroImage

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(city.name)
                        .font(.title3.weight(.semibold))
                    Text(city.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let subtitle = viewModel.wikiInfo?.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var heroImage: some View {
        Group {
            if let imageURL = viewModel.wikiInfo?.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        imagePlaceholder.overlay { ProgressView() }
                    case .failure:
                        imagePlaceholder
                    @unknown default:
                        imagePlaceholder
                    }
                }
            } else {
                imagePlaceholder
            }
        }
        .frame(height: selectedDetent == .large ? 192 : 160)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
        )
    }

    private var imagePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.34), Color.accentColor.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 7) {
                Image(systemName: "photo")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(L10n.tr("City Preview"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private var infoSection: some View {
        sectionContainer(title: L10n.tr("Info"), symbol: "text.book.closed") {
            VStack(alignment: .leading, spacing: 10) {
                if viewModel.isLoadingInfo {
                    ProgressView(L10n.tr("Loading city summary..."))
                } else if let info = viewModel.wikiInfo {
                    Text(info.subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(info.summary)
                        .font(.subheadline)
                        .lineLimit(infoLineLimit)
                    if let articleURL = info.articleURL {
                        Link(destination: articleURL) {
                            Label(L10n.tr("Read full article"), systemImage: "arrow.up.right.square")
                                .font(.footnote.weight(.semibold))
                        }
                    }
                } else {
                    Text(L10n.tr("No encyclopedia summary available for this city."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let destination = viewModel.matchedDestination {
                    Divider()
                    detailRow(L10n.tr("Climate"), destination.climate)
                    detailRow(L10n.tr("Cost Index"), String(format: "%.2f", destination.costIndex))
                    detailRow(L10n.tr("Eco Score"), String(format: "%.2f", destination.ecoScore))
                    detailRow(L10n.tr("Crowding Index"), String(format: "%.2f", destination.crowdingIndex))
                    if !destination.typicalSeason.isEmpty {
                        detailRow(L10n.tr("Best Seasons"), destination.typicalSeason.joined(separator: ", "))
                    }
                }

                if let localInsight = viewModel.matchedLocalInsight {
                    Divider()
                    Text(localInsight.summaryText)
                        .font(.subheadline)
                }
            }
        }
    }

    private var feedbackSection: some View {
        sectionContainer(title: L10n.tr("Feedback"), symbol: "star.bubble") {
            Group {
                if viewModel.feedbackEntries.isEmpty {
                    Text(L10n.tr("No community feedback for this destination yet."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        Label(L10n.tr("Traveler avg"), systemImage: "airplane")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.yellow)
                        Text("\(averageRating, specifier: "%.1f") / 5")
                            .font(.subheadline.weight(.semibold))
                            .appNumericTransition(averageRating)

                        if localAverageRating > 0 {
                            Label(L10n.tr("Local avg"), systemImage: "house.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(localAverageRating, specifier: "%.1f") / 5")
                                .font(.subheadline.weight(.semibold))
                                .appNumericTransition(localAverageRating)
                        }
                    }

                    if !topFeedbackTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(topFeedbackTags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule(style: .continuous)
                                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                                        )
                                }
                            }
                        }
                    }

                    ForEach(Array(viewModel.feedbackEntries.prefix(placeLimit)), id: \.id) { entry in
                        feedbackRow(entry)
                    }
                }
            }
        }
    }

    private func placesSection(
        title: String,
        symbol: String,
        places: [CityPlace],
        emptyMessage: String
    ) -> some View {
        sectionContainer(title: title, symbol: symbol) {
            Group {
                if viewModel.isLoadingPlaces {
                    ProgressView(L10n.tr("Loading places..."))
                } else if places.isEmpty {
                    Text(L10n.tr(emptyMessage))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(places.prefix(placeLimit))) { place in
                        placeRow(place, symbol: symbolForPlace(place))
                    }
                }
            }
        }
    }

    private func highlightedPlace(_ place: CityPlace, title: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr(title))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            placeRow(place, symbol: symbol)
        }
    }

    private func symbolForPlace(_ place: CityPlace) -> String {
        switch place.category {
        case .attractions:
            return "building.columns.fill"
        case .restaurants:
            return "fork.knife"
        case .essentials:
            return "tram.fill"
        }
    }

    private func placeRow(_ place: CityPlace, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(place.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        if let openNow = place.openNow {
                            Text(openNow ? L10n.tr("Open now") : L10n.tr("Closed"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(openNow ? .green : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill((openNow ? Color.green : Color(uiColor: .tertiaryLabel)).opacity(0.13))
                                )
                        }
                    }
                    Text(place.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 5) {
                    if let distanceLabel = place.distanceLabel {
                        Text(distanceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let deeplink = place.deeplink {
                        Link(destination: deeplink) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption.weight(.semibold))
                        }
                        .accessibilityTapTarget()
                        .accessibilityLabel(L10n.f("Open %@ in Maps", place.name))
                        .accessibilityHint(L10n.tr("Opens external map directions"))
                    }
                }
            }

            HStack(spacing: 8) {
                if let rating = place.rating {
                    Label("\(rating, specifier: "%.1f")", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
                if let reviewCount = place.reviewCount {
                    Label("\(reviewCount)", systemImage: "person.2")
                        .foregroundStyle(.secondary)
                }
                if let priceLevel = place.priceLevel {
                    Text(String(repeating: "$", count: max(1, min(priceLevel, 4))))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.weight(.semibold))

            HStack(spacing: 6) {
                if let placeType = place.placeType, !placeType.isEmpty {
                    Text(placeType)
                }
                Text(place.provider)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if let reason = place.personalizationReason, !reason.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(uiColor: .tertiarySystemGroupedBackground), Color(uiColor: .secondarySystemGroupedBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
        )
    }

    private func feedbackRow(_ entry: TravelerFeedback) -> some View {
        let translatedContent = translatedFeedbackByID[entry.id]
        let feedbackText = translatedContent?.text.nonEmpty ?? entry.text
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: index < entry.rating ? "star.fill" : "star")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(index < entry.rating ? .yellow : .secondary)
                    }
                }
                Spacer(minLength: 0)
                Label(entry.sourceType.title, systemImage: entry.sourceType.symbol)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }

            Text(feedbackText.nonEmpty ?? L10n.tr("No written comment."))
                .font(.subheadline)
                .lineLimit(3)

            Text(entry.perspectiveLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.tr(label))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }

    private func sectionContainer<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.tr(title))
                    .font(.headline)
                Spacer(minLength: 0)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardContainerStyle()
    }

    private var emptyStateCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(L10n.tr("Select a city"))
                .font(.headline)
            Text(L10n.tr("Search a city from the field above or tap anywhere on the map."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .cardContainerStyle()
    }

    private func statusMessageCard(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .cardContainerStyle()
    }

    private func recenterButton(for city: ExplorerCity) -> some View {
        Button {
            centerMap(on: city.coordinate)
        } label: {
            Image(systemName: "location.fill")
                .font(.subheadline.weight(.semibold))
                .frame(width: 38, height: 38)
                .background(
                    GlassSurface(
                        shape: Circle(),
                        fallbackMaterial: .regularMaterial
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
        .accessibilityLabel(L10n.tr("Recenter map"))
        .accessibilityHint(L10n.f("Moves map back to %@", city.name))
    }

    private func mapTapGesture(proxy: MapProxy) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                guard !viewModel.isResolvingLocation else { return }
                guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                resolveCityFromMapCoordinate(coordinate)
            }
    }

    private func searchCity() {
        let trimmed = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let config = bootstrap.travelAPIConfig

        runningTask?.cancel()
        viewModel.resetStatus()
        viewModel.isResolvingLocation = true

        runningTask = Task { @MainActor in
            let service = CityExplorerService(config: config)
            let city = await service.searchCity(query: trimmed)
            guard !Task.isCancelled else { return }

            guard let city else {
                viewModel.isResolvingLocation = false
                viewModel.statusMessage = L10n.f("No city found for \"%@\".", trimmed)
                return
            }

            presentDetailsPanel()
            centerMap(on: city.coordinate)
            viewModel.isResolvingLocation = false
            await viewModel.applySelection(city: city, homeViewModel: homeViewModel, service: service)
            Task { @MainActor in
                await refreshExploreDataIfNeeded()
                viewModel.refreshLocalMatches(homeViewModel: homeViewModel)
            }
        }
    }

    private func resolveCityFromMapCoordinate(_ coordinate: CLLocationCoordinate2D) {
        let config = bootstrap.travelAPIConfig
        runningTask?.cancel()
        viewModel.resetStatus()
        viewModel.isResolvingLocation = true

        runningTask = Task { @MainActor in
            let service = CityExplorerService(config: config)
            let city = await service.cityForCoordinate(coordinate)
            guard !Task.isCancelled else { return }

            guard let city else {
                viewModel.isResolvingLocation = false
                viewModel.statusMessage = L10n.tr("Unable to identify a city at this point.")
                return
            }

            presentDetailsPanel()
            centerMap(on: city.coordinate)
            viewModel.isResolvingLocation = false
            await viewModel.applySelection(city: city, homeViewModel: homeViewModel, service: service)
            Task { @MainActor in
                await refreshExploreDataIfNeeded()
                viewModel.refreshLocalMatches(homeViewModel: homeViewModel)
            }
        }
    }

    @MainActor
    private func refreshExploreDataIfNeeded() async {
        if bootstrap.settingsStore.isAuthenticated, !homeViewModel.isOfflineModeEnabled {
            await bootstrap.syncManager.processPendingOperations(
                context: modelContext,
                forceDownsync: true
            )
        }
        homeViewModel.refreshExploreCollections(context: modelContext)
    }

    @MainActor
    private func refreshFeedbackTranslations() async {
        let inputs = viewModel.feedbackEntries.map {
            FeedbackTranslationInput(id: $0.id, text: $0.text, tags: $0.tags)
        }
        guard !inputs.isEmpty else {
            translatedFeedbackByID = [:]
            return
        }

        translatedFeedbackByID = await bootstrap.feedbackTranslationService.translate(
            feedbacks: inputs,
            targetLanguage: L10n.preferredNarrativeLanguage,
            languageCode: L10n.preferredLanguageCode
        )
    }

    @MainActor
    private func presentDetailsPanel() {
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedTab = .forYou
            selectedDetent = .fraction(0.62)
            isPanelPresented = true
        }
    }

    @MainActor
    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.28)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
                )
            )
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension View {
    func cardContainerStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
            )
    }

    @ViewBuilder
    func appSymbolPulse<Value: Equatable>(value: Value) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.pulse, value: value)
        } else {
            self
        }
    }

    @ViewBuilder
    func appNumericTransition(_ value: Double) -> some View {
        if #available(iOS 17.0, *) {
            self.contentTransition(.numericText(value: value))
        } else {
            self
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.cityexplorer") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext
    bootstrap.prepare(context: context)

    let homeViewModel = HomeViewModel()
    homeViewModel.load(context: context, bootstrap: bootstrap)
    let viewModel = CityExplorerViewModel()

    return NavigationStack {
        CityExplorerView(
            homeViewModel: homeViewModel,
            viewModel: viewModel
        )
    }
    .environment(bootstrap)
    .modelContainer(container)
}
