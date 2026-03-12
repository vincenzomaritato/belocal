import SwiftData
import SwiftUI

struct PlannerBriefDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppBootstrap.self) private var bootstrap

    let conversation: PlannerConversation
    var onOpenLinkedChat: (() -> Void)? = nil

    @State private var heroPage = 0
    @State private var attractionInfoByKey: [String: AttractionCardLiveInfo] = [:]
    @State private var attractionLoadingKeys: Set<String> = []
    @State private var loadedSnapshot: PlannerBriefSnapshot?

    private var snapshot: PlannerBriefSnapshot? {
        loadedSnapshot ?? decodeSnapshot(from: conversation.snapshotJSON)
    }

    private var finalReport: PlannerFinalReport? { snapshot?.finalReport }
    private var answers: [String: String] { snapshot?.answers ?? [:] }
    private var destinationName: String {
        let base = answers["destination"] ?? finalReport?.destinationFocus ?? conversation.destinationHint ?? L10n.tr("Your destination")
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var freeDaysLabel: String { answers["freeDays"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    private var datesLabel: String {
        let raw = answers["seasonAndDates"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? (finalReport?.bestTravelWindow ?? L10n.tr("Flexible dates")) : raw
    }
    private var budgetLabel: String {
        let raw = finalReport?.budgetSnapshot.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? L10n.tr("Budget not specified") : raw
    }
    private var attractionCount: Int { finalReport?.attractions.count ?? 0 }

    private var heroItems: [BriefHeroItem] {
        if let report = finalReport {
            let seed = report.attractions.prefix(4).map { $0.name }
            if !seed.isEmpty {
                return seed.enumerated().map { index, title in
                    BriefHeroItem(
                        title: title,
                        subtitle: destinationName,
                        gradient: heroGradient(at: index)
                    )
                }
            }
        }

        return [
            BriefHeroItem(
                title: destinationName,
                subtitle: L10n.tr("Final Trip Brief"),
                gradient: heroGradient(at: 0)
            )
        ]
    }

    private var tags: [String] {
        let raw = answers["interests"] ?? ""
        let normalized = raw
            .replacingOccurrences(of: "/", with: "+")
            .replacingOccurrences(of: ",", with: "+")
        let parsed = normalized
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parsed.isEmpty { return Array(parsed.prefix(4)) }
        return [L10n.tr("Architecture"), L10n.style("Nature"), L10n.style("Culture")]
    }

    private var titleText: String {
        if !freeDaysLabel.isEmpty {
            return L10n.f("Explore %@ in %@", destinationName, freeDaysLabel)
        }
        if let report = finalReport, !report.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return report.headline
        }
        return L10n.f("Explore %@", destinationName)
    }

    private var overviewText: String {
        let base = finalReport?.overview ?? conversation.finalBriefOverview ?? L10n.tr("Your personalized travel brief is ready.")
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    descriptionCard

                    if let report = finalReport {
                        highlightsStrip(report)
                        strategyCard(report)
                        activitiesDeepDiveCard(report)
                        checklistCard(report)
                        notesCard(report)
                    } else {
                        fallbackCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(L10n.tr("Final Brief"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            preloadSnapshotIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if onOpenLinkedChat != nil {
                    Button(L10n.tr("Open Chat")) {
                        onOpenLinkedChat?()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityTapTarget()
                .accessibilityLabel(L10n.tr("Close final brief"))
                .accessibilityHint(L10n.tr("Dismisses this screen"))
            }
        }
    }

    private var heroCard: some View {
        VStack(spacing: 10) {
            TabView(selection: $heroPage) {
                ForEach(Array(heroItems.enumerated()), id: \.offset) { index, item in
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: item.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.18))
                                    .frame(width: 220, height: 220)
                                    .blur(radius: 30)
                                    .offset(x: 90, y: 80),
                                alignment: .bottomTrailing
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.subtitle)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(item.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                        }
                        .padding(16)
                    }
                    .cornerRadius(24)
                    .tag(index)
                    .padding(.horizontal, 1)
                }
            }
            .frame(height: 228)
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(heroItems.indices, id: \.self) { index in
                    Circle()
                        .fill(index == heroPage ? Color.primary.opacity(0.88) : Color.primary.opacity(0.22))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    private var tagsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Label(tag, systemImage: iconForTag(tag))
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
            Text(titleText)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.84)
                .lineSpacing(2)
                .lineLimit(2)

            HStack(spacing: 14) {
                metaItem(icon: "tag", text: budgetLabel)
                metaDivider
                metaItem(icon: "map", text: attractionCount > 0 ? L10n.f("%d places", attractionCount) : L10n.tr("Places soon"))
                metaDivider
                metaItem(icon: "calendar", text: datesLabel)
            }
        }
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(overviewText)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func highlightsStrip(_ report: PlannerFinalReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Highlights")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(report.dailyHighlights.prefix(5)) { day in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(day.day)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text(day.morning)
                                .font(.footnote)
                                .lineLimit(2)
                            Text(day.evening)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(width: 180, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func activitiesDeepDiveCard(_ report: PlannerFinalReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Activities Deep Dive")
            ForEach(report.attractions.prefix(10)) { attraction in
                activityInfoRow(attraction)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func strategyCard(_ report: PlannerFinalReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Execution Strategy")
            Label(report.transportStrategy, systemImage: "tram.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(L10n.f("Best window: %@", report.bestTravelWindow), systemImage: "calendar")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Label(L10n.f("Budget lens: %@", report.budgetSnapshot), systemImage: "tag.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func activityInfoRow(_ attraction: PlannerFinalAttraction) -> some View {
        let liveInfo = attractionInfo(for: attraction.name)
        let isLoading = isLoadingAttraction(attraction.name)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                activityThumbnail(for: liveInfo)

                VStack(alignment: .leading, spacing: 4) {
                    Text(attraction.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)

                    Text(liveInfo?.wikiSummary ?? liveInfo?.placeSummary ?? attraction.why)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }

            if let address = liveInfo?.address, !address.isEmpty {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let rating = liveInfo.flatMap(attractionRatingText) {
                    infoBadge(text: rating, icon: "star.fill")
                }
                if let openText = liveInfo.flatMap(attractionOpenText) {
                    infoBadge(text: openText, icon: "clock.badge.checkmark")
                }
                if let weather = liveInfo.flatMap(attractionWeatherText) {
                    infoBadge(text: weather, icon: "cloud.sun.fill")
                }
                if let price = liveInfo?.priceLevel {
                    infoBadge(text: price, icon: "eurosign.circle")
                }
            }

            if let types = liveInfo?.placeTypes, !types.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(types.prefix(4)), id: \.self) { type in
                            secondaryPill(text: friendlyPlaceType(type))
                        }
                    }
                }
            }

            if let phone = liveInfo?.phoneNumber, !phone.isEmpty {
                Label(phone, systemImage: "phone.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let nearby = liveInfo?.nearbySpots, !nearby.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("Nearby"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(nearby.prefix(5)), id: \.self) { spot in
                                secondaryPill(text: spot)
                            }
                        }
                    }
                }
            }

            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.tr("Loading live details..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if let mapsURL = liveInfo?.mapsURL {
                    actionLinkButton(title: "Maps", icon: "map", url: mapsURL)
                }
                if let wikiURL = liveInfo?.wikiArticleURL {
                    actionLinkButton(title: "Wiki", icon: "book.closed", url: wikiURL)
                }
                if let site = liveInfo?.websiteURL {
                    actionLinkButton(title: "Website", icon: "safari", url: site)
                }
            }

            Divider()
        }
        .task(id: attraction.id) {
            preloadAttractionInfoIfNeeded(for: attraction.name)
        }
    }

    @ViewBuilder
    private func activityThumbnail(for liveInfo: AttractionCardLiveInfo?) -> some View {
        let imageURL = liveInfo?.wikiImageURL
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    activityThumbnailPlaceholder
                case .empty:
                    activityThumbnailPlaceholder
                @unknown default:
                    activityThumbnailPlaceholder
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            activityThumbnailPlaceholder
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var activityThumbnailPlaceholder: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.34), Color.blue.opacity(0.24)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "photo")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.82))
        )
    }

    private func infoBadge(text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }

    private func actionLinkButton(title: String, icon: String, url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label(L10n.tr(title), systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
    }

    private func secondaryPill(text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemGroupedBackground))
            )
    }

    private func checklistCard(_ report: PlannerFinalReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Checklist")
            ForEach(Array(report.checklist.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .leading)
                    Text(item)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func notesCard(_ report: PlannerFinalReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Notes")
            ForEach(report.notes, id: \.self) { note in
                    Text(L10n.f("• %@", note))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var fallbackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Brief")
            Text(conversation.finalBriefOverview ?? L10n.tr("Open the linked chat to regenerate or refresh your final brief."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(L10n.tr(title))
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

    private func iconForTag(_ tag: String) -> String {
        let normalized = tag
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        if normalized.contains("food") || normalized.contains("cibo") {
            return "fork.knife"
        }
        if normalized.contains("nature") || normalized.contains("natura") {
            return "leaf.fill"
        }
        if normalized.contains("culture") || normalized.contains("cultura") {
            return "building.columns.fill"
        }
        if normalized.contains("adventure") || normalized.contains("avventura") {
            return "figure.hiking"
        }
        return "sparkles"
    }

    private func friendlyPlaceType(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    private func heroGradient(at index: Int) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.36, green: 0.59, blue: 0.74), Color(red: 0.58, green: 0.76, blue: 0.86)],
            [Color(red: 0.26, green: 0.42, blue: 0.58), Color(red: 0.47, green: 0.63, blue: 0.76)],
            [Color(red: 0.35, green: 0.51, blue: 0.46), Color(red: 0.56, green: 0.73, blue: 0.67)],
            [Color(red: 0.41, green: 0.46, blue: 0.69), Color(red: 0.62, green: 0.66, blue: 0.82)]
        ]
        return palettes[index % palettes.count]
    }

    private func attractionInfoKey(_ attractionName: String) -> String {
        let name = attractionName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = destinationName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name)|\(destination)"
    }

    private func attractionInfo(for attractionName: String) -> AttractionCardLiveInfo? {
        attractionInfoByKey[attractionInfoKey(attractionName)]
    }

    private func isLoadingAttraction(_ attractionName: String) -> Bool {
        attractionLoadingKeys.contains(attractionInfoKey(attractionName))
    }

    private func preloadAttractionInfoIfNeeded(for attractionName: String) {
        let key = attractionInfoKey(attractionName)
        guard attractionInfoByKey[key] == nil else { return }
        guard !attractionLoadingKeys.contains(key) else { return }

        attractionLoadingKeys.insert(key)
        let destination = destinationName
        let lookup = bootstrap.liveAttractionInfoLookup
        Task {
            let info = await lookup(attractionName, destination)
            await MainActor.run {
                attractionLoadingKeys.remove(key)
                if let info {
                    attractionInfoByKey[key] = info
                }
            }
        }
    }

    private func attractionRatingText(_ info: AttractionCardLiveInfo) -> String? {
        guard let rating = info.rating else { return nil }
        if let reviews = info.reviewCount, reviews > 0 {
            return String(format: "%.1f (%d)", rating, reviews)
        }
        return String(format: "%.1f", rating)
    }

    private func attractionOpenText(_ info: AttractionCardLiveInfo) -> String? {
        guard let openNow = info.openNow else { return nil }
        return openNow ? L10n.tr("Open now") : L10n.tr("Closed now")
    }

    private func attractionWeatherText(_ info: AttractionCardLiveInfo) -> String? {
        guard let temperature = info.temperatureC else { return nil }
        let rounded = Int(temperature.rounded())
        if let summary = info.weatherSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return "\(rounded)°C • \(summary)"
        }
        return "\(rounded)°C"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func decodeSnapshot(from snapshotJSON: String) -> PlannerBriefSnapshot? {
        guard let data = snapshotJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PlannerBriefSnapshot.self, from: data)
    }

    private func preloadSnapshotIfNeeded() {
        if loadedSnapshot != nil { return }
        if let current = decodeSnapshot(from: conversation.snapshotJSON) {
            loadedSnapshot = current
            return
        }

        let conversationID = conversation.id
        let descriptor = FetchDescriptor<PlannerConversation>(
            predicate: #Predicate { $0.id == conversationID }
        )
        guard let refreshed = try? modelContext.fetch(descriptor).first else { return }
        loadedSnapshot = decodeSnapshot(from: refreshed.snapshotJSON)
    }
}

private struct PlannerBriefSnapshot: Decodable {
    let finalReport: PlannerFinalReport?
    let answers: [String: String]?
}

private struct BriefHeroItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let gradient: [Color]
}
