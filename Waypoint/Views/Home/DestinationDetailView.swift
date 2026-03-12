import MapKit
import SwiftUI

struct DestinationDetailView: View {
    let destination: Destination
    let recommendation: RecommendationItem
    let localInsight: LocalInsight?
    let ecoAlternatives: [Destination]
    let travelerFeedback: [TravelerFeedback]

    @State private var mapPosition: MapCameraPosition

    init(
        destination: Destination,
        recommendation: RecommendationItem,
        localInsight: LocalInsight?,
        ecoAlternatives: [Destination],
        travelerFeedback: [TravelerFeedback]
    ) {
        self.destination = destination
        self.recommendation = recommendation
        self.localInsight = localInsight
        self.ecoAlternatives = ecoAlternatives
        self.travelerFeedback = travelerFeedback
        _mapPosition = State(initialValue: .region(
            MKCoordinateRegion(
                center: destination.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
            )
        ))
    }

    var body: some View {
        ZStack {
            PlannerBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    mapSection
                    keyAttributes
                    ecoAlternativesSection
                    communitySection
                }
                .padding(16)
            }
        }
        .navigationTitle(destination.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var mapSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Destination focus"))
                    .font(.headline)

                Map(position: $mapPosition) {
                    Marker(destination.name, coordinate: destination.coordinate)
                        .tint(Color.accentColor)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityLabel(L10n.f("Map of %@", destination.name))
                .accessibilityHint(L10n.tr("Shows the selected destination location"))
            }
        }
    }

    private var keyAttributes: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Key attributes"))
                    .font(.headline)

                HStack(spacing: 14) {
                    attribute(label: L10n.tr("Budget fit"), value: "\(Int(recommendation.matchScore))")
                    attribute(label: L10n.tr("Season fit"), value: destination.typicalSeason.map(L10n.season).joined(separator: " • "))
                    attribute(label: L10n.tr("Style fit"), value: destination.styles.prefix(2).map(L10n.style).joined(separator: " + "))
                }
            }
        }
    }

    private var ecoAlternativesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Eco alternatives"))
                    .font(.headline)

                if ecoAlternatives.isEmpty {
                    Text(L10n.tr("No lower-CO2 alternatives found for this style."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(ecoAlternatives, id: \.id) { option in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                    .font(.subheadline.weight(.semibold))
                                Text(L10n.f("%@ • Eco %d", option.country, Int(option.ecoScore)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(L10n.f("~%dkg", Int(option.distanceKm * 0.18)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var communitySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Community insight"))
                    .font(.headline)

                Text(localInsight?.summaryText ?? L10n.tr("No local insight available yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !travelerFeedback.isEmpty {
                    let travelerEntries = travelerFeedback.filter { $0.sourceType == .traveler }
                    let localEntries = travelerFeedback.filter { $0.sourceType == .local }

                    if !travelerEntries.isEmpty {
                        let avg = Double(travelerEntries.map(\.rating).reduce(0, +)) / Double(travelerEntries.count)
                        Text(L10n.f("Traveler average rating: %@/5 (%d)", avg.formatted(.number.precision(.fractionLength(1))), travelerEntries.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !localEntries.isEmpty {
                        let avg = Double(localEntries.map(\.rating).reduce(0, +)) / Double(localEntries.count)
                        Text(L10n.f("Local average rating: %@/5 (%d)", avg.formatted(.number.precision(.fractionLength(1))), localEntries.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func attribute(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let destination = Destination(
        name: "Copenhagen",
        country: "Denmark",
        latitude: 55.6761,
        longitude: 12.5683,
        styles: ["Design", "Culture"],
        climate: "Cool",
        costIndex: 0.74,
        ecoScore: 92,
        crowdingIndex: 0.35,
        typicalSeason: ["Summer", "Spring"],
        distanceKm: 6200
    )
    let recommendation = RecommendationItem(
        destination: destination,
        matchScore: 90,
        ecoScore: 92,
        estimatedCO2: 420,
        whyRecommended: "Low-carbon transit options and strong local sentiment.",
        breakdown: RecommendationBreakdown(
            matchScore: 0.9,
            environmentalPenalty: 0.08,
            localApprovalFactor: 0.95,
            finalScore: 89.2
        )
    )
    let insight = LocalInsight(
        destinationId: destination.id,
        sustainabilityScore: 91,
        authenticityScore: 84,
        overcrowdingScore: 36,
        summaryText: "Bike-first mobility and neighborhood businesses receive positive support."
    )
    let alternative = Destination(
        name: "Ljubljana",
        country: "Slovenia",
        latitude: 46.0569,
        longitude: 14.5058,
        styles: ["Nature", "Culture"],
        climate: "Temperate",
        costIndex: 0.49,
        ecoScore: 88,
        crowdingIndex: 0.29,
        typicalSeason: ["Spring", "Summer"],
        distanceKm: 1300
    )
    let feedback = TravelerFeedback(
        tripId: UUID(),
        rating: 5,
        tags: ["Sustainable", "Great value"],
        text: "Cycling infrastructure makes the city easy to explore.",
        crowding: 0.3,
        value: 0.85,
        sustainabilityPerception: 0.9,
        sentiment: "positive"
    )

    return NavigationStack {
        DestinationDetailView(
            destination: destination,
            recommendation: recommendation,
            localInsight: insight,
            ecoAlternatives: [alternative],
            travelerFeedback: [feedback]
        )
    }
}
