import Foundation
import SwiftData
import SwiftUI

struct PostOnboardingWelcomeView: View {
    @Environment(AppBootstrap.self) private var bootstrap

    @Bindable var homeViewModel: HomeViewModel
    let onContinue: () -> Void

    @State private var isRevealed = false
    @State private var isContinuing = false

    private var profile: UserProfile? {
        homeViewModel.userProfile
    }

    var body: some View {
        ZStack {
            AuthBackgroundView()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                        .offset(y: isRevealed ? 0 : 22)
                        .opacity(isRevealed ? 1 : 0)

                    summaryCard
                        .offset(y: isRevealed ? 0 : 30)
                        .opacity(isRevealed ? 1 : 0)

                    styleCard
                        .offset(y: isRevealed ? 0 : 38)
                        .opacity(isRevealed ? 1 : 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 120)
                .animation(.spring(response: 0.45, dampingFraction: 0.9).delay(0.05), value: isRevealed)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Divider()

                Button {
                    guard !isContinuing else { return }
                    isContinuing = true
                    bootstrap.settingsStore.markOnboardingWelcomeSeen()
                    onContinue()
                } label: {
                    HStack(spacing: 8) {
                        if isContinuing {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Enter Waypoint")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(isContinuing)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .background(.ultraThinMaterial)
        }
        .onAppear {
            withAnimation {
                isRevealed = true
            }
        }
    }

    private var heroCard: some View {
        GlassCard(cornerRadius: 30) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.9), Color.red.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .accessibilityHidden(true)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Welcome back")
                            .font(.title3.weight(.bold))
                        Text("Profile completed successfully")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Hi \(resolvedName), here's how Waypoint will personalize suggestions, itineraries, and ranking.")
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.88))
            }
        }
    }

    private var summaryCard: some View {
        GlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Profile snapshot")
                    .font(.headline)

                VStack(spacing: 10) {
                    snapshotRow(label: "Travelers", value: "\(profile?.peopleDefault ?? 2)")
                    snapshotRow(label: "Budget", value: budgetLabel)
                    snapshotRow(label: "Departure", value: homeLabel)
                    snapshotRow(label: "Eco", value: ecoLabel)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preferred seasons")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if resolvedSeasons.isEmpty {
                        Text("No preference set")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(resolvedSeasons, id: \.self) { season in
                                Text(season)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(Color.orange.opacity(0.14))
                                    )
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private var styleCard: some View {
        GlassCard(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Editorial focus")
                    .font(.headline)

                ForEach(styleBreakdown, id: \.key) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.key)
                                .font(.footnote.weight(.semibold))
                            Spacer()
                            Text("\(Int((item.value * 100).rounded()))%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        GeometryReader { proxy in
                            let width = max(proxy.size.width * item.value, 8)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.black.opacity(0.07))
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.orange.opacity(0.65))
                                    .frame(width: width)
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
        }
    }

    private func snapshotRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private var resolvedName: String {
        let value = profile?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Traveler" : value
    }

    private var resolvedSeasons: [String] {
        (profile?.preferredSeasons ?? [])
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var budgetLabel: String {
        guard let profile else { return "EUR 1200 - EUR 3200" }
        return "EUR \(Int(profile.budgetMin)) - EUR \(Int(profile.budgetMax))"
    }

    private var homeLabel: String {
        guard let profile else { return "Rome, Italy" }

        let isRome =
            abs(profile.homeLatitude - TravelDistanceCalculator.defaultHomeLatitude) < 0.0001 &&
            abs(profile.homeLongitude - TravelDistanceCalculator.defaultHomeLongitude) < 0.0001

        if isRome {
            return "Rome, Italy"
        }

        return String(format: "%.2f, %.2f", profile.homeLatitude, profile.homeLongitude)
    }

    private var ecoLabel: String {
        guard let profile else { return "60%" }
        return "\(Int((profile.ecoSensitivity * 100).rounded()))%"
    }

    private var styleBreakdown: [(key: String, value: Double)] {
        guard let profile else {
            return [("Culture", 0.25), ("Food", 0.25), ("Nature", 0.25), ("Beach", 0.25)]
        }

        let orderedKeys = ["Culture", "Food", "Nature", "Beach"]
        let weights = profile.travelStyleWeights
        let sum = max(weights.values.reduce(0, +), 0.001)

        return orderedKeys.map { key in
            let raw = weights[key] ?? 0
            return (key, raw / sum)
        }
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.welcome") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext
    bootstrap.prepare(context: context)

    let homeViewModel = HomeViewModel()
    homeViewModel.load(context: context, bootstrap: bootstrap)

    return PostOnboardingWelcomeView(homeViewModel: homeViewModel, onContinue: {})
        .environment(bootstrap)
        .modelContainer(container)
}
