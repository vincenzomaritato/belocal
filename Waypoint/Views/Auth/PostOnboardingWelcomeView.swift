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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
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
                .frame(maxWidth: 720)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 132)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.45, dampingFraction: 0.9).delay(0.05), value: isRevealed)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Divider()

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr("Profile ready"))
                            .font(.subheadline.weight(.semibold))
                        Text(L10n.tr("Open the app with your preferences already applied."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

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

                            Text(L10n.tr("Enter BeLocal"))
                                .font(.headline.weight(.semibold))

                            if !isContinuing {
                                Image(systemName: "arrow.right")
                                    .font(.caption.weight(.bold))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .foregroundStyle(.white)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.23, green: 0.47, blue: 0.97),
                                    Color(red: 0.13, green: 0.34, blue: 0.84)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isContinuing)
                }
                .padding(.horizontal, 18)
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.23, green: 0.47, blue: 0.97),
                                    Color(red: 0.36, green: 0.74, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "checkmark")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("Welcome to BeLocal"))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(L10n.tr("Setup complete"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.f("Hi %@, your profile is ready to drive recommendations, ranking, and planner suggestions from the first screen.", resolvedName))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)

                HStack(spacing: 10) {
                    welcomePill(title: homeLabel, icon: "location.fill")
                    welcomePill(title: budgetLabel, icon: "creditcard.fill")
                }
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(0.64))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.76), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 18, x: 0, y: 12)
    }

    private var summaryCard: some View {
        WelcomeSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("Profile snapshot"))
                    .font(.headline)

                VStack(spacing: 10) {
                    snapshotRow(label: L10n.tr("Travelers"), value: "\(profile?.peopleDefault ?? 2)")
                    snapshotRow(label: L10n.tr("Budget"), value: budgetLabel)
                    snapshotRow(label: L10n.tr("Departure"), value: homeLabel)
                    snapshotRow(label: L10n.tr("Eco"), value: ecoLabel)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("Preferred seasons"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if resolvedSeasons.isEmpty {
                        Text(L10n.tr("No preference set"))
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
        WelcomeSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("Editorial focus"))
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
                                    .fill(Color.black.opacity(0.06))
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(red: 0.23, green: 0.47, blue: 0.97).opacity(0.72))
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
        return value.isEmpty ? L10n.tr("Traveler") : value
    }

    private var resolvedSeasons: [String] {
        (profile?.preferredSeasons ?? [])
            .filter { !$0.isEmpty }
            .map(L10n.season)
            .sorted()
    }

    private var budgetLabel: String {
        guard let profile else { return L10n.tr("EUR 1200 - EUR 3200") }
        return L10n.f("EUR %d - EUR %d", Int(profile.budgetMin), Int(profile.budgetMax))
    }

    private var homeLabel: String {
        guard let profile else { return L10n.tr("Not set") }
        let textual = [profile.homeCity, profile.homeCountry]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return textual.isEmpty ? L10n.tr("Not set") : textual
    }

    private var ecoLabel: String {
        guard let profile else { return "60%" }
        return "\(Int((profile.ecoSensitivity * 100).rounded()))%"
    }

    private var styleBreakdown: [(key: String, value: Double)] {
        guard let profile else {
            return [(L10n.style("Culture"), 0.25), (L10n.style("Food"), 0.25), (L10n.style("Nature"), 0.25), (L10n.style("Beach"), 0.25)]
        }

        let orderedKeys = ["Culture", "Food", "Nature", "Beach"]
        let weights = profile.travelStyleWeights
        let sum = max(weights.values.reduce(0, +), 0.001)

        return orderedKeys.map { key in
            let raw = weights[key] ?? 0
            return (L10n.style(key), raw / sum)
        }
    }

    private func welcomePill(title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.04), in: Capsule(style: .continuous))
        .foregroundStyle(.secondary)
    }
}

private struct WelcomeSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.62))
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.74), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 10)
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
