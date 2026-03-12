import SwiftUI
import UIKit

struct FeedbackFormView: View {
    @Bindable var viewModel: TripDetailViewModel
    let locationOptions: [FeedbackLocationOption]
    let onSave: (FeedbackLocationOption) -> Void

    private let availableTags = ["Family-friendly", "Crowded", "Great value", "Sustainable", "Authentic", "Food scene"]
    @FocusState private var isNotesFocused: Bool
    @State private var highlightDestinationValidation = false
    @State private var isDestinationPickerPresented = false
    @State private var destinationSearchText = ""

    private var selectedTripId: UUID? {
        viewModel.feedbackDraft.selectedTripId
    }

    private var selectedLocation: FeedbackLocationOption? {
        guard let selectedTripId else { return nil }
        return locationOptions.first(where: { $0.tripId == selectedTripId })
    }

    private var completionProgress: Double {
        var completed = 0
        if selectedTripId != nil { completed += 1 }
        if !viewModel.feedbackDraft.tags.isEmpty || !trimmedNotes.isEmpty { completed += 1 }

        let sliders = [
            viewModel.feedbackDraft.crowding,
            viewModel.feedbackDraft.value,
            viewModel.feedbackDraft.sustainabilityPerception
        ]
        let defaults = [0.45, 0.7, 0.75]
        let changedCount = zip(sliders, defaults).filter { abs($0 - $1) > 0.001 }.count
        if changedCount >= 2 { completed += 1 }

        completed += 1

        return Double(completed) / 4.0
    }

    private var trimmedNotes: String {
        viewModel.feedbackDraft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredLocationOptions: [FeedbackLocationOption] {
        let query = destinationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return locationOptions }

        return locationOptions.filter { option in
            option.destinationName.lowercased().contains(query)
                || option.country.lowercased().contains(query)
                || option.periodLabel.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        introCard
                        if let feedbackError = viewModel.feedbackError {
                            Label(feedbackError, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                        destinationCard
                        ratingCard
                        highlightsCard
                        metricsCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(L10n.tr("Feedback Studio"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveFeedback()
                    } label: {
                        if viewModel.savingFeedback {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 19, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .appSymbolPulse(value: selectedTripId != nil)
                        }
                    }
                    .tint(.accentColor)
                    .disabled(viewModel.savingFeedback || selectedTripId == nil)
                    .accessibilityLabel(L10n.tr("Save feedback"))
                    .accessibilityHint(L10n.tr("Saves your rating, notes, and destination feedback"))
                }
            }
            .sheet(
                isPresented: $isDestinationPickerPresented,
                onDismiss: { destinationSearchText = "" }
            ) {
                destinationPickerSheet
            }
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "star.bubble.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                    )
                    .appSymbolPulse(value: Int(completionProgress * 100))

                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.tr("Trip feedback"))
                        .font(.headline)
                    Text(L10n.tr("Help Planner Studio personalize your next recommendations."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(Int(completionProgress * 100))%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .appNumericTextTransition(Double(Int(completionProgress * 100)))
                    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: completionProgress)
            }

            ProgressView(value: completionProgress)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .animation(.easeInOut(duration: 0.2), value: completionProgress)

            if let selectedLocation {
                HStack(spacing: 6) {
                    Image(systemName: selectedLocation.sourceType.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.f("Perspective for this destination: %@", selectedLocation.perspectiveLabel))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .appleCardSurface()
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: L10n.tr("Destination"),
                subtitle: locationOptions.isEmpty
                    ? L10n.tr("No completed trips available")
                    : L10n.f("%d trips available", locationOptions.count)
            )

            if locationOptions.isEmpty {
                Text(L10n.tr("There are no completed trips available."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent {
                    Button(selectedLocation == nil ? L10n.tr("Choose") : L10n.tr("Change")) {
                        isDestinationPickerPresented = true
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(selectedLocation == nil ? L10n.tr("Choose destination") : L10n.tr("Change destination"))
                    .accessibilityHint(L10n.tr("Opens the list of available trips"))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedLocation.map { "\($0.destinationName), \($0.country)" } ?? L10n.tr("No destination selected"))
                                .fontWeight(.semibold)
                                .foregroundStyle(selectedLocation == nil ? .secondary : .primary)
                            Text(selectedLocation?.periodLabel ?? L10n.tr("Open destination list"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                if let selectedLocation {
                    Label(selectedLocation.perspectiveLabel, systemImage: selectedLocation.sourceType.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .appleCardSurface()
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(highlightDestinationValidation ? 0.55 : 0), lineWidth: 1.5)
        )
        .scaleEffect(highlightDestinationValidation ? 1.01 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: highlightDestinationValidation)
    }

    private var destinationPickerSheet: some View {
        NavigationStack {
            List {
                if filteredLocationOptions.isEmpty {
                    ContentUnavailableView(
                        L10n.tr("No results"),
                        systemImage: "magnifyingglass",
                        description: Text(L10n.tr("Try searching with a different city or country."))
                    )
                    .listRowBackground(Color.clear)
                } else {
                    Section(L10n.tr("Destinations")) {
                        ForEach(filteredLocationOptions) { option in
                            destinationSheetRow(option)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.tr("Select destination"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $destinationSearchText, prompt: L10n.tr("Search city, country, or period"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.tr("Close")) {
                        isDestinationPickerPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func destinationSheetRow(_ option: FeedbackLocationOption) -> some View {
        let isSelected = selectedTripId == option.tripId

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                viewModel.feedbackDraft.selectedTripId = option.tripId
                viewModel.feedbackError = nil
                highlightDestinationValidation = false
            }
            isDestinationPickerPresented = false
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(option.destinationName), \(option.country)")
                            .foregroundStyle(.primary)
                        Text(option.periodLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "airplane.departure")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("\(option.destinationName), \(option.country)")
        .accessibilityValue(isSelected ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(L10n.tr("Select this destination for feedback"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            Text(option.perspectiveLabel)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.13))
                )
                .foregroundStyle(Color.accentColor)
                .padding(.top, 4)
        }
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: L10n.tr("Rating"), subtitle: ratingLabel)

            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { star in
                    let isActive = star <= viewModel.feedbackDraft.rating
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                            viewModel.feedbackDraft.rating = star
                        }
                    } label: {
                        Image(systemName: isActive ? "star.fill" : "star")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(isActive ? .yellow : .secondary)
                            .scaleEffect(star == viewModel.feedbackDraft.rating ? 1.05 : 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityTapTarget()
                    .accessibilityLabel(star == 1 ? L10n.f("%d star", star) : L10n.f("%d stars", star))
                    .accessibilityValue(isActive ? L10n.tr("Selected") : L10n.tr("Not selected"))
                    .accessibilityHint(L10n.tr("Sets overall trip rating"))
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }

                Spacer(minLength: 0)

                Text("\(viewModel.feedbackDraft.rating)/5")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .appNumericTextTransition(Double(viewModel.feedbackDraft.rating))
                    .animation(.spring(response: 0.32, dampingFraction: 0.84), value: viewModel.feedbackDraft.rating)
            }
        }
        .appleCardSurface()
    }

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: L10n.tr("Highlights"), subtitle: L10n.tr("Quick tags and an optional note"))

            FlexibleTagLayout(tags: availableTags, selected: viewModel.feedbackDraft.tags) { tag in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.84)) {
                    if viewModel.feedbackDraft.tags.contains(tag) {
                        viewModel.feedbackDraft.tags.remove(tag)
                    } else {
                        viewModel.feedbackDraft.tags.insert(tag)
                    }
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.feedbackDraft.text)
                    .focused($isNotesFocused)
                    .frame(minHeight: 116)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(L10n.tr("Feedback notes"))
                    .accessibilityHint(L10n.tr("Optional notes about your travel experience"))

                if trimmedNotes.isEmpty {
                    Text(L10n.tr("How was it? What would you recommend to other travelers?"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }

            Text("\(viewModel.feedbackDraft.text.count) characters")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .appleCardSurface()
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: L10n.tr("Perception"), subtitle: L10n.tr("Balance crowding, value, and sustainability"))

            metricSlider(
                title: L10n.tr("Crowding"),
                icon: "person.3.fill",
                value: $viewModel.feedbackDraft.crowding,
                lowCaption: L10n.tr("Quiet"),
                highCaption: L10n.tr("Very crowded")
            )

            metricSlider(
                title: L10n.tr("Value for money"),
                icon: "banknote.fill",
                value: $viewModel.feedbackDraft.value,
                lowCaption: L10n.tr("Low"),
                highCaption: L10n.tr("Excellent")
            )

            metricSlider(
                title: L10n.tr("Sustainability"),
                icon: "leaf.fill",
                value: $viewModel.feedbackDraft.sustainabilityPerception,
                lowCaption: L10n.tr("Low"),
                highCaption: L10n.tr("High")
            )
        }
        .appleCardSurface()
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var ratingLabel: String {
        switch viewModel.feedbackDraft.rating {
        case 1: return L10n.tr("Needs improvement")
        case 2: return L10n.tr("Below expectations")
        case 3: return L10n.tr("Good")
        case 4: return L10n.tr("Very good")
        case 5: return L10n.tr("Excellent")
        default: return L10n.tr("Tap a star")
        }
    }

    private func metricSlider(
        title: String,
        icon: String,
        value: Binding<Double>,
        lowCaption: String,
        highCaption: String
    ) -> some View {
        let score = Int(value.wrappedValue * 100)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .appSymbolPulse(value: score)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Text("\(score)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .appNumericTextTransition(Double(score))
                    .animation(.spring(response: 0.28, dampingFraction: 0.84), value: score)
            }

            Slider(value: value, in: 0...1)
                .tint(Color.accentColor)
                .accessibilityLabel(title)
                .accessibilityValue(L10n.f("%d out of 100", score))
                .accessibilityHint(L10n.f("%@ to %@", lowCaption, highCaption))

            HStack {
                Text(lowCaption)
                Spacer()
                Text(value.wrappedValue < 0.34 ? lowCaption : value.wrappedValue > 0.66 ? highCaption : L10n.tr("Balanced"))
                    .fontWeight(.semibold)
                Spacer()
                Text(highCaption)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        )
    }

    private func saveFeedback() {
        isNotesFocused = false
        viewModel.feedbackError = nil

        guard let selectedLocation else {
            viewModel.feedbackError = L10n.tr("Choose a visited destination first.")
            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                highlightDestinationValidation = true
            }
            return
        }

        onSave(selectedLocation)
    }
}

private struct FlexibleTagLayout: View {
    let tags: [String]
    let selected: Set<String>
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    onTap(tag)
                } label: {
                        Text(L10n.tr(tag))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected.contains(tag) ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    selected.contains(tag)
                                        ? Color.accentColor.opacity(0.14)
                                        : Color(uiColor: .tertiarySystemGroupedBackground)
                                )
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(
                                    selected.contains(tag)
                                        ? Color.accentColor.opacity(0.42)
                                        : Color(uiColor: .separator).opacity(0.14),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .accessibilityLabel(L10n.tr(tag))
                .accessibilityValue(selected.contains(tag) ? L10n.tr("Selected") : L10n.tr("Not selected"))
                .accessibilityHint(L10n.tr("Double-tap to toggle this highlight tag"))
                .accessibilityAddTraits(selected.contains(tag) ? .isSelected : [])
            }
        }
    }
}

private extension View {
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

    func appleCardSurface() -> some View {
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
}

#Preview {
    let destination = Destination(
        name: "Reykjavik",
        country: "Iceland",
        latitude: 64.1466,
        longitude: -21.9426,
        styles: ["Nature", "Adventure"],
        climate: "Cool",
        costIndex: 0.78,
        ecoScore: 90,
        crowdingIndex: 0.33,
        typicalSeason: ["Summer", "Winter"],
        distanceKm: 4200
    )
    let trip = Trip(
        userId: UUID(),
        destinationId: destination.id,
        startDate: .now,
        endDate: Calendar.current.date(byAdding: .day, value: 5, to: .now) ?? .now,
        transportType: .plane,
        people: 2,
        budgetSpent: 2800,
        co2Estimated: 520,
        ecoScoreSnapshot: 88
    )
    let viewModel = TripDetailViewModel(trip: trip, destination: destination)
    viewModel.feedbackDraft.text = "Loved the geothermal pools and quiet neighborhoods."
    viewModel.feedbackDraft.tags = ["Sustainable", "Authentic"]

    return FeedbackFormView(
        viewModel: viewModel,
        locationOptions: [
            FeedbackLocationOption(
                tripId: trip.id,
                destinationId: destination.id,
                destinationName: "Reykjavik",
                country: "Iceland",
                destinationLatitude: destination.latitude,
                destinationLongitude: destination.longitude,
                sourceType: .traveler,
                authorHomeCity: "Milan",
                authorHomeCountry: "Italy",
                periodLabel: "1 Jun - 6 Jun"
            )
        ]
    ) { _ in }
}
