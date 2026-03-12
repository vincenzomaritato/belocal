import SwiftData
import SwiftUI
import UIKit

struct PlannerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(AppBootstrap.self) private var bootstrap

    @Query(sort: [SortDescriptor(\PlannerConversation.updatedAt, order: .reverse)])
    private var conversations: [PlannerConversation]

    @Bindable var homeViewModel: HomeViewModel
    let launchRequest: PlannerLaunchRequest?
    var onProfileTap: (() -> Void)? = nil

    @State private var query = ""
    @State private var selectedTab: PlannerTab = .myPlan
    @State private var isChatPresented = false
    @State private var isBriefDetailPresented = false
    @State private var initialChatPrompt = ""
    @State private var initialChatPrefill: PlannerSuggestionPrefill?
    @State private var selectedConversation: PlannerConversation?
    @State private var selectedBriefConversation: PlannerConversation?
    @State private var lastHandledLaunchRequestID: UUID?

    @Namespace private var searchBarNamespace

    private let liquidAccent = Color.accentColor

    private var myChatConversations: [PlannerConversation] {
        conversations
    }

    private var myPlanBriefConversations: [PlannerConversation] {
        conversations.filter { $0.hasFinalBrief }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PlannerBackgroundView()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        heroSearchStack
                        tabs
                        tabContent
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 22)
                }
                .allowsHitTesting(!isChatPresented)
                .blur(radius: isChatPresented ? 1.8 : 0)
                .scaleEffect(isChatPresented ? 0.985 : 1, anchor: .top)
                .overlay {
                    if isChatPresented {
                        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.12)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                }

                if isChatPresented {
                    PlannerChatView(
                        homeViewModel: homeViewModel,
                        isPresented: $isChatPresented,
                        initialPrompt: initialChatPrompt,
                        prefill: initialChatPrefill,
                        conversation: selectedConversation,
                        searchBarNamespace: searchBarNamespace
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.985, anchor: .bottom)),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                    .zIndex(20)
                }
            }
            .animation(.spring(response: 0.48, dampingFraction: 0.88), value: isChatPresented)
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                if let onProfileTap {
                    ToolbarItem(placement: .topBarLeading) {
                        ProfileToolbarButton(action: onProfileTap)
                    }
                }
            }
            .toolbar(isChatPresented ? .hidden : .visible, for: .navigationBar)
            .toolbar(isChatPresented ? .hidden : .visible, for: .tabBar)
            .onAppear {
                handleLaunchRequestIfNeeded()
            }
            .onChange(of: launchRequest?.id) { _, _ in
                handleLaunchRequestIfNeeded()
            }
            .sheet(isPresented: $isBriefDetailPresented, onDismiss: {
                selectedBriefConversation = nil
            }) {
                if let conversation = selectedBriefConversation {
                    NavigationStack {
                        PlannerBriefDetailView(conversation: conversation) {
                            let conversationToOpen = conversation
                            isBriefDetailPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                openSavedChat(conversationToOpen)
                            }
                        }
                    }
                    .presentationDragIndicator(.visible)
                } else {
                    EmptyView()
                }
            }
        }
    }

    private var header: some View {
        Text(L10n.tr("Your next adventures!"))
            .font(.system(size: 38, weight: .bold, design: .rounded))
            .tracking(-0.6)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .padding(.top, 4)
    }

    private var heroStrip: some View {
        HStack(spacing: -12) {
            ForEach(Array(heroCards.enumerated()), id: \.offset) { index, card in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: card.gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 82, height: 66)
                    .overlay {
                        Image(systemName: card.symbol)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.55), lineWidth: 1)
                    )
                    .rotationEffect(.degrees(heroTilt[index]))
                    .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 6)
                    .zIndex(Double(index))
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroSearchStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            heroStrip
                .padding(.leading, 6)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .overlay(alignment: .bottomLeading) {
            searchBar
                .offset(y: 42)
                .zIndex(1)
        }
        .padding(.top, 2)
        .padding(.bottom, 54)
    }

    private var searchBar: some View {
        Button {
            openNewChat(prompt: query.trimmingCharacters(in: .whitespacesAndNewlines), prefill: nil)
            selectedTab = .myChat
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.94), liquidAccent.opacity(0.88)],
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: 26
                        )
                    )
                    .frame(width: 34, height: 34)
                    .blur(radius: 0.25)

                Text(query.isEmpty ? L10n.tr("Start a new planner chat") : query)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "mic.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .searchGlassSurface(cornerRadius: 28, isDark: colorScheme == .dark)
        .matchedGeometryEffect(
            id: "planner-chat-search-bar",
            in: searchBarNamespace,
            properties: .frame,
            anchor: .center,
            isSource: !isChatPresented
        )
        .opacity(isChatPresented ? 0.01 : 1)
        .allowsHitTesting(!isChatPresented)
        .accessibilityLabel(L10n.tr("Start planner chat"))
        .accessibilityValue(query.isEmpty ? L10n.tr("No prompt") : query)
        .accessibilityHint(L10n.tr("Opens Planner Studio to create a new conversation"))
    }

    private var tabs: some View {
        HStack {
            HStack(spacing: 20) {
                tabButton(for: .myPlan)
                tabButton(for: .myChat)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == .myPlan {
            myPlanContent
        } else {
            myChatContent
        }
    }

    private var myPlanContent: some View {
        LazyVStack(spacing: 12) {
            if myPlanBriefConversations.isEmpty {
                emptyCard(
                    title: L10n.tr("No final briefs yet"),
                    subtitle: L10n.tr("Create or complete a chat in My Chat. Final briefs linked to chats will appear here.")
                )
            } else {
                ForEach(myPlanBriefConversations, id: \.id) { conversation in
                    briefCard(conversation)
                        .contextMenu {
                            Button(role: .destructive) {
                                deleteConversation(conversation)
                            } label: {
                                Label(L10n.tr("Delete chat and brief"), systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private var myChatContent: some View {
        VStack(spacing: 12) {
            newChatCard

            if myChatConversations.isEmpty {
                emptyCard(
                    title: L10n.tr("No chats yet"),
                    subtitle: L10n.tr("Start a new chat. It will be saved automatically and listed here.")
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(myChatConversations, id: \.id) { conversation in
                        chatRow(conversation)
                            .contextMenu {
                                Button(role: .destructive) {
                                    deleteConversation(conversation)
                                } label: {
                                    Label(L10n.tr("Delete chat and brief"), systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
    }

    private var newChatCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("My Chat"))
                .font(.system(size: 21, weight: .bold, design: .rounded))
            Text(L10n.tr("Continue existing chats or start a new one. Every new chat is saved automatically."))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                openNewChat(prompt: "", prefill: nil)
            } label: {
                Label(L10n.tr("New Chat"), systemImage: "plus.bubble.fill")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor, Color(red: 0.94, green: 0.55, blue: 0.18)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidSurface(cornerRadius: 22, isDark: colorScheme == .dark)
    }

    private func chatRow(_ conversation: PlannerConversation) -> some View {
        Button {
            openSavedChat(conversation)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    Text(conversation.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if conversation.hasFinalBrief {
                        Text(L10n.tr("Brief"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.accentColor.opacity(0.18))
                            )
                    }
                }

                Text(conversation.lastMessagePreview.isEmpty ? L10n.tr("Open chat") : conversation.lastMessagePreview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidSurface(cornerRadius: 18, isDark: colorScheme == .dark)
        }
        .buttonStyle(.plain)
    }

    private func briefCard(_ conversation: PlannerConversation) -> some View {
        Button {
            openSavedBrief(conversation)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(conversation.finalBriefHeadline ?? conversation.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Image(systemName: "doc.text.fill")
                        .foregroundStyle(Color.accentColor)
                }

                if let destinationHint = conversation.destinationHint, !destinationHint.isEmpty {
                    Label(destinationHint, systemImage: "location.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(conversation.finalBriefOverview ?? L10n.tr("Open this linked chat to view and update the full brief."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack {
                    Text(conversation.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(L10n.tr("Open brief"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidSurface(cornerRadius: 22, isDark: colorScheme == .dark)
        }
        .buttonStyle(.plain)
    }

    private func emptyCard(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .liquidSurface(cornerRadius: 22, isDark: colorScheme == .dark)
    }

    private func tabButton(for tab: PlannerTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Text(tab.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                Capsule()
                    .fill(selectedTab == tab ? liquidAccent : Color.clear)
                    .frame(height: 3)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityTapTarget()
        .accessibilityLabel(tab.label)
        .accessibilityValue(selectedTab == tab ? L10n.tr("Selected") : L10n.tr("Not selected"))
        .accessibilityHint(L10n.tr("Switch planner section"))
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
    }

    private var heroTilt: [Double] { [-5, 2, -3, 3, -2] }

    private var heroCards: [HeroCard] {
        [
            HeroCard(symbol: "bubble.left.and.bubble.right.fill", gradient: [Color(red: 0.31, green: 0.61, blue: 0.94), Color(red: 0.52, green: 0.78, blue: 0.99)]),
            HeroCard(symbol: "doc.text.fill", gradient: [Color(red: 0.38, green: 0.72, blue: 0.91), Color(red: 0.62, green: 0.89, blue: 0.98)]),
            HeroCard(symbol: "building.columns.fill", gradient: [Color(red: 0.35, green: 0.54, blue: 0.79), Color(red: 0.52, green: 0.77, blue: 0.9)]),
            HeroCard(symbol: "tram.fill", gradient: [Color(red: 0.44, green: 0.62, blue: 0.52), Color(red: 0.63, green: 0.81, blue: 0.66)]),
            HeroCard(symbol: "leaf.fill", gradient: [Color(red: 0.34, green: 0.74, blue: 0.51), Color(red: 0.63, green: 0.89, blue: 0.66)])
        ]
    }

    private func openNewChat(prompt: String, prefill: PlannerSuggestionPrefill?) {
        selectedConversation = nil
        initialChatPrompt = prompt
        initialChatPrefill = prefill
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            isChatPresented = true
        }
    }

    private func openSavedChat(_ conversation: PlannerConversation) {
        selectedConversation = conversation
        initialChatPrompt = ""
        initialChatPrefill = nil
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            isChatPresented = true
        }
    }

    private func openSavedBrief(_ conversation: PlannerConversation) {
        selectedBriefConversation = latestConversation(for: conversation.id) ?? conversation
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isBriefDetailPresented = true
        }
    }

    private func latestConversation(for id: UUID) -> PlannerConversation? {
        let descriptor = FetchDescriptor<PlannerConversation>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func deleteConversation(_ conversation: PlannerConversation) {
        let linkedTripId = conversation.linkedTripId

        if let linkedTripId {
            let activities = (try? modelContext.fetch(FetchDescriptor<ActivityItem>())) ?? []
            for item in activities where item.tripId == linkedTripId {
                bootstrap.syncManager.enqueue(
                    type: .deleteActivity,
                    payload: ["activityId": item.id.uuidString],
                    context: modelContext
                )
                modelContext.delete(item)
            }

            let feedbackEntries = (try? modelContext.fetch(FetchDescriptor<TravelerFeedback>())) ?? []
            for item in feedbackEntries where item.tripId == linkedTripId {
                bootstrap.syncManager.enqueue(
                    type: .deleteFeedback,
                    payload: ["feedbackId": item.id.uuidString],
                    context: modelContext
                )
                modelContext.delete(item)
            }

            let trips = (try? modelContext.fetch(FetchDescriptor<Trip>())) ?? []
            if let trip = trips.first(where: { $0.id == linkedTripId }) {
                bootstrap.syncManager.enqueue(
                    type: .deleteTrip,
                    payload: ["tripId": trip.id.uuidString],
                    context: modelContext
                )
                modelContext.delete(trip)
            }
        }

        if selectedConversation?.id == conversation.id {
            selectedConversation = nil
            if isChatPresented {
                isChatPresented = false
            }
        }

        if selectedBriefConversation?.id == conversation.id {
            selectedBriefConversation = nil
            if isBriefDetailPresented {
                isBriefDetailPresented = false
            }
        }

        modelContext.delete(conversation)
        try? modelContext.save()
        homeViewModel.load(context: modelContext, bootstrap: bootstrap)
        Task {
            await bootstrap.syncManager.processPendingOperations(context: modelContext)
        }
    }

    private func handleLaunchRequestIfNeeded() {
        guard let launchRequest else { return }
        guard launchRequest.id != lastHandledLaunchRequestID else { return }

        lastHandledLaunchRequestID = launchRequest.id
        query = launchRequest.prefill.destinationLabel
        selectedTab = .myChat
        openNewChat(prompt: launchRequest.prompt, prefill: launchRequest.prefill)
    }
}

private struct HeroCard {
    let symbol: String
    let gradient: [Color]
}

private enum PlannerTab {
    case myPlan
    case myChat

    var label: String {
        switch self {
        case .myPlan: return L10n.tr("My Plan")
        case .myChat: return L10n.tr("My Chat")
        }
    }
}

private extension View {
    func searchGlassSurface(cornerRadius: CGFloat, isDark: Bool) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(isDark ? 0.34 : 0.22), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isDark ? 0.24 : 0.10), radius: 14, x: 0, y: 8)
    }

    func liquidSurface(cornerRadius: CGFloat, isDark: Bool) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(isDark ? 0.30 : 0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(isDark ? 0.20 : 0.08), radius: 12, x: 0, y: 7)
    }
}

#Preview {
    let defaults = UserDefaults(suiteName: "preview.planner") ?? .standard
    let settingsStore = AppSettingsStore(defaults: defaults)
    let bootstrap = AppBootstrap(settingsStore: settingsStore)
    let container = SwiftDataStack.makeContainer(inMemory: true)
    let context = container.mainContext
    bootstrap.prepare(context: context)

    let homeViewModel = HomeViewModel()
    homeViewModel.load(context: context, bootstrap: bootstrap)

    return PlannerView(
        homeViewModel: homeViewModel,
        launchRequest: nil
    )
    .environment(bootstrap)
    .modelContainer(container)
}
