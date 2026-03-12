import SwiftUI

struct DestinationCardView: View {
    let item: RecommendationItem

    private var normalizedFinalScore: CGFloat {
        let normalized = item.breakdown.finalScore / 100
        return CGFloat(min(max(normalized, 0), 1))
    }

    private var displayMatchPercentage: Int {
        min(max(item.matchScore, 0), 100)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.destination.name)
                            .font(.title3.weight(.semibold))
                        Label(item.destination.country, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                    scoreBadge
                }

                if !item.destination.styles.isEmpty {
                    Text(item.destination.styles.prefix(3).map(L10n.style).joined(separator: " • "))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statLine(symbol: "leaf", label: L10n.tr("Eco"), value: "\(item.ecoScore)")
                    statLine(symbol: "aqi.medium", label: "CO2", value: L10n.f("%dkg", Int(item.estimatedCO2)))
                    statLine(symbol: "person.3", label: L10n.tr("Match"), value: L10n.f("%d%%", displayMatchPercentage))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("Why it fits"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.whyRecommended)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Text(L10n.tr("View destination details"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.f("%@, %@. Match %d percent. Eco score %d. %@", item.destination.name, item.destination.country, displayMatchPercentage, item.ecoScore, item.whyRecommended)
        )
        .accessibilityHint(L10n.tr("Opens destination details and planning actions"))
    }

    private var scoreBadge: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 4)

            Circle()
                .trim(from: 0, to: normalizedFinalScore)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(item.breakdown.finalScore))")
                .font(.caption.weight(.bold))
                .monospacedDigit()
        }
        .frame(width: 42, height: 42)
        .accessibilityLabel(L10n.f("Destination score %d out of 100", Int(item.breakdown.finalScore)))
    }

    private func statLine(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(label) \(value)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

#Preview {
    let destination = Destination(
        name: "Lisbon",
        country: "Portugal",
        latitude: 38.7223,
        longitude: -9.1393,
        styles: ["Culture", "Food"],
        climate: "Mild",
        costIndex: 0.55,
        ecoScore: 82,
        crowdingIndex: 0.42,
        typicalSeason: ["Spring", "Autumn"],
        distanceKm: 1900
    )
    let item = RecommendationItem(
        destination: destination,
        matchScore: 88,
        ecoScore: 82,
        estimatedCO2: 320,
        whyRecommended: "Great culture and food, with strong shoulder-season value.",
        breakdown: RecommendationBreakdown(
            matchScore: 86,
            environmentalPenalty: 0.12,
            localApprovalFactor: 0.92,
            finalScore: 87.5
        )
    )

    return DestinationCardView(item: item)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
