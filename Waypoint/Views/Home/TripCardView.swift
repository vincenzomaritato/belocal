import SwiftUI

struct TripCardView: View {
    let trip: Trip
    let destination: Destination?

    private var tripDays: Int {
        max(Calendar.current.dateComponents([.day], from: trip.startDate, to: trip.endDate).day ?? 0, 0) + 1
    }

    private var ecoProgress: Double {
        min(max(trip.ecoScoreSnapshot / 100, 0), 1)
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destination?.name ?? "Unknown Destination")
                            .font(.title3.weight(.semibold))
                        Label(destination?.country ?? "", systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text("\(tripDays) days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Label(
                    "\(trip.startDate.formatted(date: .abbreviated, time: .omitted)) - \(trip.endDate.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    statItem(symbol: "wallet.pass", value: "€\(Int(trip.budgetSpent))")
                    statItem(symbol: "leaf", value: "\(Int(trip.co2Estimated))kg")
                    statItem(symbol: "person.2", value: "\(trip.people)")
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Eco score")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(trip.ecoScoreSnapshot))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }

                    ProgressView(value: ecoProgress)
                        .tint(.accentColor)
                }
            }
            .frame(width: 268, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(destination?.name ?? "Unknown destination"), \(destination?.country ?? ""). \(tripDays) days. Budget \(Int(trip.budgetSpent)) euros. Emissions \(Int(trip.co2Estimated)) kilograms. Eco score \(Int(trip.ecoScoreSnapshot))."
        )
        .accessibilityHint("Opens this trip timeline and feedback")
    }

    private func statItem(symbol: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
    }
}

#Preview {
    let destination = Destination(
        name: "Valencia",
        country: "Spain",
        latitude: 39.4699,
        longitude: -0.3763,
        styles: ["Beach", "Food"],
        climate: "Warm",
        costIndex: 0.52,
        ecoScore: 76,
        crowdingIndex: 0.44,
        typicalSeason: ["Spring", "Summer"],
        distanceKm: 1750
    )
    let trip = Trip(
        userId: UUID(),
        destinationId: destination.id,
        startDate: .now,
        endDate: Calendar.current.date(byAdding: .day, value: 4, to: .now) ?? .now,
        transportType: .train,
        people: 2,
        budgetSpent: 2100,
        co2Estimated: 630,
        ecoScoreSnapshot: 74
    )

    return TripCardView(trip: trip, destination: destination)
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
