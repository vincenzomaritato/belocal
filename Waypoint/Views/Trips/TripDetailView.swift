import SwiftData
import SwiftUI

struct TripDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var viewModel: TripDetailViewModel
    @Bindable var homeViewModel: HomeViewModel
    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var translatedFeedbackByID: [UUID: FeedbackTranslationContent] = [:]

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

    private var destinationName: String {
        viewModel.destination?.name ?? L10n.tr("Trip")
    }

    private var destinationCountry: String {
        viewModel.destination?.country ?? L10n.tr("Destination")
    }

    private var tripDays: Int {
        max(Calendar.current.dateComponents([.day], from: viewModel.trip.startDate, to: viewModel.trip.endDate).day ?? 0, 0) + 1
    }

    private var dateRangeLabel: String {
        "\(viewModel.trip.startDate.formatted(date: .abbreviated, time: .omitted)) - \(viewModel.trip.endDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private var tripTags: [String] {
        var raw: [String] = []
        if let destination = viewModel.destination {
            raw.append(contentsOf: destination.styles.prefix(3).map(L10n.style))
        }
        raw.append(viewModel.trip.transportType.localizedTitle)
        raw.append(viewModel.trip.people == 1 ? L10n.tr("Solo") : L10n.f("%d Travelers", viewModel.trip.people))

        var seen = Set<String>()
        let deduped = raw.filter { seen.insert($0).inserted }
        return Array(deduped.prefix(5))
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemGroupedBackground),
                    Color(uiColor: .secondarySystemGroupedBackground).opacity(0.9)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    tagsRow
                    titleMetaBlock
                    dividerLine
                    snapshotSection
                    activitiesSection
                    feedbackSummarySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(L10n.tr("Trip Details"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: feedbackTranslationTaskID) {
            await refreshFeedbackTranslations()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L10n.tr("Leave Feedback")) {
                        viewModel.feedbackDraft.selectedTripId = nil
                        viewModel.showFeedbackSheet = true
                    }

                    Divider()

                    Button(L10n.tr("Edit Trip")) {
                        showEditSheet = true
                    }

                    Button(L10n.tr("Delete Trip"), role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(L10n.tr("Trip actions"))
                .accessibilityHint(L10n.tr("Open options to leave feedback, edit, or delete this trip"))
            }
        }
        .onAppear {
            viewModel.load(context: modelContext)
        }
        .sheet(isPresented: $viewModel.showFeedbackSheet) {
            FeedbackFormView(viewModel: viewModel, locationOptions: feedbackLocationOptions) { selectedLocation in
                viewModel.saveFeedback(
                    context: modelContext,
                    syncManager: bootstrap.syncManager,
                    selectedLocation: selectedLocation
                ) {
                    homeViewModel.load(context: modelContext, bootstrap: bootstrap)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditSheet) {
            TripEditSheetView(trip: viewModel.trip) { startDate, endDate, transportType, people, budget in
                applyTripEdit(
                    startDate: startDate,
                    endDate: endDate,
                    transportType: transportType,
                    people: people,
                    budget: budget
                )
            }
        }
        .confirmationDialog(
            L10n.tr("Delete this trip?"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("Delete Trip"), role: .destructive) {
                deleteTrip()
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("This removes the trip and all related activities/feedback."))
        }
        .alert(L10n.tr("Operation failed"), isPresented: tripMutationErrorBinding) {
            Button(L10n.tr("OK"), role: .cancel) {
                viewModel.tripMutationError = nil
            }
        } message: {
            Text(viewModel.tripMutationError ?? L10n.tr("Something went wrong."))
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.49, blue: 0.66),
                            Color(red: 0.54, green: 0.69, blue: 0.82)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 230, height: 230)
                        .blur(radius: 32)
                        .offset(x: 90, y: 90),
                    alignment: .bottomTrailing
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(destinationCountry)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))

                Text(destinationName)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 10) {
                    heroPill(icon: "calendar", text: dateRangeLabel)
                    heroPill(icon: viewModel.trip.transportType.iconName, text: viewModel.trip.transportType.localizedTitle)
                }
            }
            .padding(16)
        }
        .frame(height: 220)
    }

    private func heroPill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .foregroundStyle(.white)
    }

    private var tagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tripTags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var titleMetaBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.f("Your %d-Day Plan in %@", tripDays, destinationName))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.84)
                .lineSpacing(2)
                .lineLimit(2)

            HStack(spacing: 14) {
                metaItem(icon: "eurosign.circle", text: "€\(Int(viewModel.trip.budgetSpent.rounded()))")
                metaDivider
                metaItem(icon: "map", text: L10n.f("%d days", tripDays))
                metaDivider
                metaItem(icon: "leaf", text: L10n.f("%dkg CO2", Int(viewModel.trip.co2Estimated.rounded())))
            }
        }
    }

    private var snapshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.tr("Trip Snapshot"))

            HStack(spacing: 8) {
                infoBadge(text: viewModel.trip.transportType.localizedTitle, icon: viewModel.trip.transportType.iconName)
                infoBadge(text: L10n.f("%d people", viewModel.trip.people), icon: "person.2.fill")
                infoBadge(text: L10n.f("Eco %d", Int(viewModel.trip.ecoScoreSnapshot.rounded())), icon: "leaf.fill")
            }

            Label(L10n.f("Date range: %@", dateRangeLabel), systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(L10n.f("Budget spent: €%d", Int(viewModel.trip.budgetSpent.rounded())), systemImage: "wallet.pass.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label(L10n.f("Estimated emissions: %d kg CO2", Int(viewModel.trip.co2Estimated.rounded())), systemImage: "aqi.medium")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L10n.tr("Eco score"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Int(viewModel.trip.ecoScoreSnapshot.rounded())) / 100")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(max(viewModel.trip.ecoScoreSnapshot / 100, 0), 1))
                    .tint(.accentColor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.tr("Saved Activities"))

            if viewModel.activities.isEmpty {
                Text(L10n.tr("No activities saved for this trip yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.activities, id: \.id) { activity in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.14))
                                .frame(width: 28, height: 28)
                            Image(systemName: icon(for: activity.type))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(activity.title)
                                .font(.subheadline.weight(.semibold))
                            Text(activity.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if activity.id != viewModel.activities.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var feedbackSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.tr("Community Feedback"))

            if viewModel.feedbackEntries.isEmpty {
                Text(L10n.tr("No feedback yet. Tap Leave Feedback to enrich recommendations."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                let travelerCount = viewModel.feedbackEntries.filter { $0.sourceType == .traveler }.count
                let localCount = viewModel.feedbackEntries.filter { $0.sourceType == .local }.count
                HStack(spacing: 8) {
                    infoBadge(
                        text: travelerCount == 1 ? L10n.f("%d traveler", travelerCount) : L10n.f("%d travelers", travelerCount),
                        icon: FeedbackSourceType.traveler.symbol
                    )
                    infoBadge(
                        text: localCount == 1 ? L10n.f("%d local", localCount) : L10n.f("%d locals", localCount),
                        icon: FeedbackSourceType.local.symbol
                    )
                }

                ForEach(viewModel.feedbackEntries, id: \.id) { feedback in
                    let translatedContent = translatedFeedbackByID[feedback.id]
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(String(repeating: "★", count: feedback.rating))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.yellow)
                            Label(feedback.sourceType.title, systemImage: feedback.sourceType.symbol)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        }

                        Text(feedback.perspectiveLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(translatedContent?.text.nonEmpty ?? feedback.text)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        let translatedTags = translatedContent?.tags ?? feedback.tags
                        if !translatedTags.isEmpty {
                            Text(translatedTags.joined(separator: " • "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func timelineDate(for day: Int) -> String {
        guard let date = Calendar.current.date(byAdding: .day, value: day - 1, to: viewModel.trip.startDate) else {
            return ""
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var feedbackTranslationTaskID: String {
        let payload = viewModel.feedbackEntries.map { entry in
            "\(entry.id.uuidString)|\(entry.text)|\(entry.tags.joined(separator: "||"))"
        }
        .joined(separator: ":::")
        return "\(L10n.preferredLanguageCode)|\(payload)"
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

    private func timelineStatus(for day: Int) -> String {
        if day == 1 { return L10n.tr("Arrival and orientation") }
        if day == tripDays { return L10n.tr("Departure and wrap-up") }
        return L10n.tr("Exploration and planned activities")
    }

    private func infoBadge(text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
            .padding(.top, 2)
    }

    private var metaDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 14)
    }

    private func metaItem(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func icon(for type: ActivityType) -> String {
        switch type {
        case .flight: return "airplane"
        case .restaurant: return "fork.knife"
        case .activity: return "figure.walk"
        case .brief: return "doc.text.fill"
        }
    }

    private func tripPeriodLabel(for trip: Trip) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: trip.startDate, to: trip.endDate)
    }

    private var tripMutationErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.tripMutationError != nil },
            set: { newValue in
                if !newValue {
                    viewModel.tripMutationError = nil
                }
            }
        )
    }

    private func applyTripEdit(
        startDate: Date,
        endDate: Date,
        transportType: TransportType,
        people: Int,
        budget: Double
    ) {
        let safePeople = max(1, people)
        let distanceKm = max(viewModel.destination?.distanceKm ?? 0, 0)
        let estimatedCO2 = bootstrap.co2Estimator.estimate(
            distanceKm: distanceKm,
            transportType: transportType,
            people: safePeople
        )
        let ecoSnapshot = viewModel.destination?.ecoScore ?? viewModel.trip.ecoScoreSnapshot

        viewModel.updateTrip(
            context: modelContext,
            syncManager: bootstrap.syncManager,
            startDate: startDate,
            endDate: endDate,
            transportType: transportType,
            people: safePeople,
            budgetSpent: budget,
            co2Estimated: estimatedCO2,
            ecoScoreSnapshot: ecoSnapshot
        ) {
            showEditSheet = false
            homeViewModel.load(
                context: modelContext,
                bootstrap: bootstrap,
                preferOffline: homeViewModel.isOfflineModeEnabled
            )
            Task {
                await bootstrap.syncManager.processPendingOperations(context: modelContext)
            }
        }
    }

    private func deleteTrip() {
        viewModel.deleteTrip(context: modelContext, syncManager: bootstrap.syncManager) {
            homeViewModel.load(
                context: modelContext,
                bootstrap: bootstrap,
                preferOffline: homeViewModel.isOfflineModeEnabled
            )
            Task {
                await bootstrap.syncManager.processPendingOperations(context: modelContext)
            }
            dismiss()
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct TripEditSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var transportType: TransportType
    @State private var people: Int
    @State private var budgetText: String

    let onSave: (Date, Date, TransportType, Int, Double) -> Void

    init(
        trip: Trip,
        onSave: @escaping (Date, Date, TransportType, Int, Double) -> Void
    ) {
        _startDate = State(initialValue: trip.startDate)
        _endDate = State(initialValue: trip.endDate)
        _transportType = State(initialValue: trip.transportType)
        _people = State(initialValue: max(1, trip.people))
        _budgetText = State(initialValue: String(Int(trip.budgetSpent.rounded())))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L10n.tr("Dates")) {
                    DatePicker(L10n.tr("Start"), selection: $startDate, displayedComponents: .date)
                    DatePicker(
                        L10n.tr("End"),
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: .date
                    )
                }

                Section(L10n.tr("Trip Setup")) {
                    Picker(L10n.tr("Transport"), selection: $transportType) {
                        ForEach(TransportType.allCases, id: \.rawValue) { type in
                            Text(type.localizedTitle).tag(type)
                        }
                    }
                    Stepper(value: $people, in: 1...12) {
                        Text(L10n.f("People: %d", people))
                    }
                    TextField(L10n.tr("Budget (€)"), text: $budgetText)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(L10n.tr("Edit Trip"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.tr("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("Save")) {
                        let budget = max(0, Double(budgetText.replacingOccurrences(of: ",", with: ".")) ?? 0)
                        onSave(startDate, max(endDate, startDate), transportType, people, budget)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.tripdetail") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext

    let destination = Destination(
        name: "Kyoto",
        country: "Japan",
        latitude: 35.0116,
        longitude: 135.7681,
        styles: ["Culture", "Nature"],
        climate: "Temperate",
        costIndex: 0.72,
        ecoScore: 80,
        crowdingIndex: 0.58,
        typicalSeason: ["Spring", "Autumn"],
        distanceKm: 9800
    )
    context.insert(destination)

    let trip = Trip(
        userId: UUID(),
        destinationId: destination.id,
        startDate: Calendar.current.date(byAdding: .day, value: -10, to: .now) ?? .now,
        endDate: Calendar.current.date(byAdding: .day, value: -5, to: .now) ?? .now,
        transportType: .plane,
        people: 2,
        budgetSpent: 3200,
        co2Estimated: 780,
        ecoScoreSnapshot: 78
    )
    context.insert(trip)

    let activity = ActivityItem(
        tripId: trip.id,
        type: .activity,
        title: "Shrine Walk",
        note: "Early morning visit"
    )
    context.insert(activity)

    let feedback = TravelerFeedback(
        tripId: trip.id,
        rating: 4,
        tags: ["Authentic", "Food scene"],
        text: "Peaceful neighborhoods beyond the main temples.",
        crowding: 0.5,
        value: 0.7,
        sustainabilityPerception: 0.75,
        sentiment: "positive"
    )
    context.insert(feedback)
    try? context.save()

    let homeViewModel = HomeViewModel()
    homeViewModel.destinations = [destination]

    let viewModel = TripDetailViewModel(trip: trip, destination: destination)

    return NavigationStack {
        TripDetailView(viewModel: viewModel, homeViewModel: homeViewModel)
    }
    .environment(bootstrap)
    .modelContainer(container)
}
