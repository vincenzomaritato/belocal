import Foundation
import Observation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PlannerChatMessage: Identifiable, Hashable, Codable {
    enum Sender: String, Hashable, Codable {
        case user
        case assistant
    }

    let id: UUID
    let sender: Sender
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), sender: Sender, text: String, createdAt: Date = .now) {
        self.id = id
        self.sender = sender
        self.text = text
        self.createdAt = createdAt
    }
}

struct PlannerQuestionStep: Identifiable, Hashable {
    enum Key: String, CaseIterable, Identifiable, Hashable {
        case destination
        case seasonAndDates
        case freeDays
        case travelers
        case travelersProfile
        case budget
        case interests
        case transportation
        case activities

        var id: String { rawValue }
    }

    let key: Key
    let title: String
    let subtitle: String
    let icon: String
    let options: [String]
    let placeholder: String
    let skipValue: String

    var id: Key { key }
}

struct PlannerSchemaNode: Identifiable, Hashable {
    let id: PlannerQuestionStep.Key
    let title: String
    let icon: String
    let value: String?
    let isCompleted: Bool
    let isCurrent: Bool
}

struct PlannerAnswerSummary: Identifiable, Hashable {
    let id: PlannerQuestionStep.Key
    let title: String
    let value: String
}

enum PlannerSmartAction: String, Identifiable, Hashable, CaseIterable {
    case attractions
    case hiddenGems
    case foodSpots
    case familyFriendly
    case optimizeBudget
    case transportTactics
    case rainyBackup
    case bookingTimeline
    case finalizeBrief
    case refreshBrief

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attractions:
            return "Top attractions"
        case .hiddenGems:
            return "Hidden gems"
        case .foodSpots:
            return "Food spots"
        case .familyFriendly:
            return "Family mode"
        case .optimizeBudget:
            return "Optimize budget"
        case .transportTactics:
            return "Smart transport"
        case .rainyBackup:
            return "Rain backup plan"
        case .bookingTimeline:
            return "Booking priorities"
        case .finalizeBrief:
            return "Finalize brief"
        case .refreshBrief:
            return "Refresh brief"
        }
    }

    var icon: String {
        switch self {
        case .attractions:
            return "building.columns.fill"
        case .hiddenGems:
            return "sparkles"
        case .foodSpots:
            return "fork.knife"
        case .familyFriendly:
            return "figure.2.and.child.holdinghands"
        case .optimizeBudget:
            return "eurosign.bank.building"
        case .transportTactics:
            return "tram.fill"
        case .rainyBackup:
            return "cloud.rain.fill"
        case .bookingTimeline:
            return "checklist.checked"
        case .finalizeBrief:
            return "doc.text.fill"
        case .refreshBrief:
            return "arrow.clockwise"
        }
    }
}

struct PlannerActionGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let actions: [PlannerSmartAction]
}

struct PlannerFinalAttraction: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let why: String
    let bestTime: String
    let estimatedCost: String

    init(
        id: UUID = UUID(),
        name: String,
        why: String,
        bestTime: String,
        estimatedCost: String
    ) {
        self.id = id
        self.name = name
        self.why = why
        self.bestTime = bestTime
        self.estimatedCost = estimatedCost
    }
}

struct PlannerDayHighlight: Identifiable, Hashable, Codable {
    let id: UUID
    let day: String
    let morning: String
    let afternoon: String
    let evening: String
    let rainFallback: String

    init(
        id: UUID = UUID(),
        day: String,
        morning: String,
        afternoon: String,
        evening: String,
        rainFallback: String
    ) {
        self.id = id
        self.day = day
        self.morning = morning
        self.afternoon = afternoon
        self.evening = evening
        self.rainFallback = rainFallback
    }
}

struct PlannerFinalReport: Hashable, Codable {
    let headline: String
    let overview: String
    let destinationFocus: String
    let bestTravelWindow: String
    let budgetSnapshot: String
    let transportStrategy: String
    let attractions: [PlannerFinalAttraction]
    let dailyHighlights: [PlannerDayHighlight]
    let checklist: [String]
    let notes: [String]
    let generatedAt: Date
}

enum PlannerConversationStage: String, Equatable, Codable {
    case guided
    case generating
    case freeform
}

enum PlannerAttractionCardAction: Hashable {
    case details
    case fitInDayPlan
    case findAlternative

    var title: String {
        switch self {
        case .details:
            return "Details"
        case .fitInDayPlan:
            return "Add to plan"
        case .findAlternative:
            return "Alternative"
        }
    }
}

@MainActor
@Observable
final class PlannerChatViewModel {
    private static let travelKeywordHints: [String] = [
        "travel", "trip", "vacation", "holiday", "itinerary", "destination", "flight", "hotel",
        "booking", "visa", "transport", "train", "bus", "metro", "airport", "museum", "attraction",
        "attractions", "activity", "activities", "things to do", "restaurant", "food", "budget", "weather", "season", "beach", "mountain",
        "viaggio", "viaggiare", "vacanza", "itinerario", "destinazione", "voli", "volo", "hotel", "attivita", "attività", "attrazioni",
        "prenotazione", "trasporto", "treno", "aeroporto", "museo", "attrazione", "ristorante",
        "cibo", "budget", "meteo", "stagione", "spiaggia", "montagna", "tour"
    ]
    private static let shortAllowedReplies: Set<String> = [
        "ok", "okay", "va bene", "perfetto", "continua", "next", "si", "sì", "no", "grazie", "thanks"
    ]
    private static let nonTravelHardBlockHints: [String] = [
        "programmazione", "programmare", "swiftui", "swift", "python", "javascript", "java", "typescript",
        "codice", "coding", "debug", "bug", "stack trace",
        "matematica", "equazione", "derivata", "integrale", "algebra", "geometria",
        "ricetta", "cucinare", "calorie", "dieta", "allenamento", "palestra",
        "bitcoin", "crypto", "trading", "borsa", "azioni", "forex",
        "politica", "elezioni", "notizie", "news",
        "oroscopo", "astrologia"
    ]

    var messages: [PlannerChatMessage] = []
    var composerText = ""
    var isSending = false
    var isGeneratingFinalReport = false
    var isPersistingBrief = false
    var errorMessage: String?
    var stage: PlannerConversationStage = .guided
    var finalReport: PlannerFinalReport?

    private(set) var currentStepIndex = 0
    private(set) var answers: [PlannerQuestionStep.Key: String] = [:]

    private var previousResponseID: String?
    private var hasAutofiredInitialPrompt = false
    private var lastAppliedPrefillSignature: String?
    private var hasAutoGeneratedFinalReport = false
    private var liveActivitiesSearchProvider: ((SearchInput) async -> [ActivityOption])?
    private var attractionInfoProvider: (@Sendable (String, String?) async -> AttractionCardLiveInfo?)?
    private var modelContext: ModelContext?
    private var persistedConversation: PlannerConversation?
    private var hasLoadedPersistedConversation = false
    private(set) var attractionInfoByKey: [String: AttractionCardLiveInfo] = [:]
    private var attractionInfoLoadingKeys: Set<String> = []

    private let questionSteps = PlannerQuestionStep.flow

    init() {
        initializeConversation()
    }

    var currentQuestion: PlannerQuestionStep? {
        guard stage == .guided else { return nil }
        return questionSteps[safe: currentStepIndex]
    }

    var completedQuestionCount: Int {
        answers.count
    }

    var totalQuestionCount: Int {
        questionSteps.count
    }

    var progressValue: Double {
        guard totalQuestionCount > 0 else { return 0 }
        return Double(completedQuestionCount) / Double(totalQuestionCount)
    }

    var progressLabel: String {
        "\(completedQuestionCount)/\(totalQuestionCount)"
    }

    var quickOptions: [String] {
        currentQuestion?.options ?? []
    }

    var composerPlaceholder: String {
        currentQuestion?.placeholder ?? "Ask for variants, alternatives, or money-saving tips..."
    }

    var isBusy: Bool {
        isSending || isGeneratingFinalReport || isPersistingBrief
    }

    var contextualActionGroups: [PlannerActionGroup] {
        guard stage != .guided else { return [] }

        var groups: [PlannerActionGroup] = []

        if let destination = answers[.destination], !destination.isEmpty {
            groups.append(
                PlannerActionGroup(
                    id: "explore",
                    title: "Explore \(destination)",
                    subtitle: "Interactive components generated from your context",
                    actions: [.attractions, .hiddenGems, .foodSpots, .familyFriendly]
                )
            )
        }

        if answers[.budget] != nil || answers[.transportation] != nil {
            groups.append(
                PlannerActionGroup(
                    id: "optimize",
                    title: "Plan optimization",
                    subtitle: "Logistics, costs, and fallback options",
                    actions: [.optimizeBudget, .transportTactics, .rainyBackup, .bookingTimeline]
                )
            )
        }

        let reportActions: [PlannerSmartAction] = finalReport == nil
            ? [.finalizeBrief]
            : [.refreshBrief]

        groups.append(
            PlannerActionGroup(
                id: "brief",
                title: "Executive brief",
                subtitle: "Complete final report ready to use",
                actions: reportActions
            )
        )

        return groups
    }

    var schemaNodes: [PlannerSchemaNode] {
        questionSteps.map { step in
            let value = answers[step.key]
            return PlannerSchemaNode(
                id: step.key,
                title: step.title,
                icon: step.icon,
                value: value,
                isCompleted: value != nil,
                isCurrent: currentQuestion?.key == step.key
            )
        }
    }

    var answerSummaries: [PlannerAnswerSummary] {
        questionSteps.compactMap { step in
            guard let value = answers[step.key] else { return nil }
            return PlannerAnswerSummary(id: step.key, title: shortLabel(for: step.key), value: value)
        }
    }

    func sendInitialPromptIfNeeded(_ prompt: String, service: any OpenAIChatServing) async {
        guard !hasAutofiredInitialPrompt else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        hasAutofiredInitialPrompt = true

        if stage == .guided, answers[.destination] == nil {
            await acceptGuidedAnswer(trimmed, service: service)
        } else {
            await sendToAssistant(userText: trimmed, service: service)
        }
    }

    func sendCurrentMessage(service: any OpenAIChatServing) async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composerText = ""

        if stage != .guided, shouldGenerateFinalReport(for: text) {
            messages.append(.init(sender: .user, text: text))
            await generateFinalReport(service: service, isManualRequest: true)
            return
        }

        if stage == .guided {
            await acceptGuidedAnswer(text, service: service)
        } else {
            await sendToAssistant(userText: text, service: service)
        }
    }

    func submitQuickOption(_ option: String, service: any OpenAIChatServing) async {
        guard stage == .guided else {
            await sendToAssistant(userText: option, service: service)
            return
        }
        await acceptGuidedAnswer(option, service: service)
    }

    func submitSurpriseOption(service: any OpenAIChatServing) async {
        guard let option = currentQuestion?.options.randomElement() else { return }
        await acceptGuidedAnswer(option, service: service)
    }

    func skipCurrentQuestion(service: any OpenAIChatServing) async {
        guard let question = currentQuestion else { return }
        await acceptGuidedAnswer(question.skipValue, service: service)
    }

    func restartPlannerJourney() {
        previousResponseID = nil
        hasAutofiredInitialPrompt = false
        lastAppliedPrefillSignature = nil
        hasAutoGeneratedFinalReport = false
        attractionInfoByKey.removeAll()
        attractionInfoLoadingKeys.removeAll()
        currentStepIndex = 0
        answers.removeAll()
        composerText = ""
        errorMessage = nil
        stage = .guided
        finalReport = nil
        isGeneratingFinalReport = false
        isPersistingBrief = false
        initializeConversation()
        hasLoadedPersistedConversation = true
        saveConversationSnapshotIfPossible()
    }

    func applySuggestionPrefillIfNeeded(_ prefill: PlannerSuggestionPrefill) {
        let signature = "\(prefill.destinationLabel)|\(prefill.budgetLabel)|\(prefill.interestsLabel)"
        guard lastAppliedPrefillSignature != signature else { return }
        lastAppliedPrefillSignature = signature

        previousResponseID = nil
        hasAutofiredInitialPrompt = true
        attractionInfoByKey.removeAll()
        attractionInfoLoadingKeys.removeAll()
        currentStepIndex = 0
        answers.removeAll()
        composerText = ""
        errorMessage = nil
        stage = .guided
        finalReport = nil
        hasAutoGeneratedFinalReport = false
        isGeneratingFinalReport = false
        isPersistingBrief = false

        answers[.destination] = prefill.destinationLabel
        answers[.freeDays] = "\(prefill.suggestedDays) days"
        answers[.budget] = prefill.budgetLabel
        answers[.interests] = prefill.interestsLabel
        answers[.activities] = "Balanced"

        advanceToNextUnansweredStep()

        messages = [
            PlannerChatMessage(
                sender: .assistant,
                text: "Planner Studio active. We will build your trip with a guided canvas: season, days, people, budget, interests, transportation, and activities."
            ),
            PlannerChatMessage(
                sender: .assistant,
                text: """
                I loaded the recommended suggestion:
                - Destination: \(prefill.destinationLabel)
                - Suggested duration: \(prefill.suggestedDays) days
                - Interests: \(prefill.interestsLabel)
                - Budget: \(prefill.budgetLabel)
                - Activity pace: Balanced
                """
            )
        ]

        if let question = currentQuestion {
            messages.append(.init(sender: .assistant, text: questionPrompt(for: question)))
        }

        saveConversationSnapshotIfPossible()
    }

    @discardableResult
    func configurePersistence(
        context: ModelContext,
        existingConversation: PlannerConversation?
    ) -> Bool {
        modelContext = context

        if let existingConversation {
            let isSameConversation = persistedConversation?.id == existingConversation.id
            persistedConversation = existingConversation

            if !isSameConversation {
                hasLoadedPersistedConversation = loadConversationSnapshot(from: existingConversation)
            } else if !hasLoadedPersistedConversation {
                hasLoadedPersistedConversation = loadConversationSnapshot(from: existingConversation)
            }

            saveConversationSnapshotIfPossible()
            return hasLoadedPersistedConversation
        }

        if persistedConversation == nil {
            let created = PlannerConversation(
                title: "New chat",
                createdAt: .now,
                updatedAt: .now,
                snapshotJSON: ""
            )
            context.insert(created)
            persistedConversation = created
            saveConversationSnapshotIfPossible()
        }

        return false
    }

    func configureLiveActivitiesSearchIfNeeded(
        _ provider: @escaping (SearchInput) async -> [ActivityOption]
    ) {
        guard liveActivitiesSearchProvider == nil else { return }
        liveActivitiesSearchProvider = provider
    }

    func configureAttractionInfoProviderIfNeeded(
        _ provider: @escaping @Sendable (String, String?) async -> AttractionCardLiveInfo?
    ) {
        guard attractionInfoProvider == nil else { return }
        attractionInfoProvider = provider
    }

    func attractionInfo(for attraction: PlannerFinalAttraction) -> AttractionCardLiveInfo? {
        attractionInfoByKey[attractionInfoKey(for: attraction.name)]
    }

    func preloadAttractionInfoIfNeeded(for attraction: PlannerFinalAttraction) {
        let key = attractionInfoKey(for: attraction.name)
        guard attractionInfoByKey[key] == nil else { return }
        guard !attractionInfoLoadingKeys.contains(key) else { return }
        guard let provider = attractionInfoProvider else { return }

        attractionInfoLoadingKeys.insert(key)

        let destination = answers[.destination]
        let attractionName = attraction.name

        Task {
            let liveInfo = await provider(attractionName, destination)
            await MainActor.run {
                self.attractionInfoLoadingKeys.remove(key)
                guard let liveInfo else { return }
                self.attractionInfoByKey[key] = liveInfo
            }
        }
    }

    func isLoadingAttractionInfo(for attraction: PlannerFinalAttraction) -> Bool {
        attractionInfoLoadingKeys.contains(attractionInfoKey(for: attraction.name))
    }

    func runContextualAction(_ action: PlannerSmartAction, service: any OpenAIChatServing) async {
        switch action {
        case .finalizeBrief, .refreshBrief:
            messages.append(.init(sender: .user, text: action.title))
            await generateFinalReport(service: service, isManualRequest: true)
        default:
            let payload = actionPrompt(for: action)
            await sendToAssistant(displayText: action.title, payload: payload, service: service)
        }
        saveConversationSnapshotIfPossible()
    }

    func runAttractionCardAction(
        _ action: PlannerAttractionCardAction,
        attraction: PlannerFinalAttraction,
        service: any OpenAIChatServing
    ) async {
        let destination = answers[.destination] ?? "the selected destination"
        let context = formattedAnswers()

        let display: String
        let payload: String

        switch action {
        case .details:
            display = "Details about \(attraction.name)"
            payload = """
            Planner context:
            \(context)

            Attraction selected:
            - Name: \(attraction.name)
            - Why: \(attraction.why)
            - Best time: \(attraction.bestTime)
            - Estimated cost: \(attraction.estimatedCost)

            Request:
            Give a practical mini-guide for this attraction in \(destination):
            - exact best slot
            - how to get there
            - expected queue
            - booking strategy
            - nearby food/coffee stop

            Respond in the user's language, concise, polished Markdown.
            """
        case .fitInDayPlan:
            display = "Add \(attraction.name) to my plan"
            payload = """
            Planner context:
            \(context)

            Attraction selected:
            - Name: \(attraction.name)
            - Best time: \(attraction.bestTime)
            - Estimated cost: \(attraction.estimatedCost)

            Request:
            Integrate this attraction into a realistic day plan with:
            - Morning / Afternoon / Evening slots
            - transfer time estimates
            - one rain fallback
            - budget impact for that day

            Respond in the user's language, concise, polished Markdown.
            """
        case .findAlternative:
            display = "Alternative to \(attraction.name)"
            payload = """
            Planner context:
            \(context)

            Attraction selected:
            - Name: \(attraction.name)
            - Why: \(attraction.why)
            - Estimated cost: \(attraction.estimatedCost)

            Request:
            Propose 3 strong alternatives in \(destination), each with:
            - why it matches the same intent
            - best time
            - estimated cost
            - when it is better than the original

            Respond in the user's language, concise, polished Markdown.
            """
        }

        await sendToAssistant(displayText: display, payload: payload, service: service)
        saveConversationSnapshotIfPossible()
    }

    func saveFinalBriefToMyPlan(
        context: ModelContext,
        homeViewModel: HomeViewModel,
        bootstrap: AppBootstrap
    ) {
        guard !isPersistingBrief else { return }
        guard let report = finalReport else {
            messages.append(.init(sender: .assistant, text: "Generate the Final Trip Brief first, then save it to My Plan."))
            return
        }
        guard let profile = homeViewModel.userProfile else {
            messages.append(.init(sender: .assistant, text: "I cannot save yet because your profile is not available."))
            return
        }

        guard let destination = resolveDestination(from: answers[.destination], homeViewModel: homeViewModel) else {
            messages.append(.init(sender: .assistant, text: "I cannot map this destination to your local catalog. Try selecting a known destination first."))
            return
        }

        isPersistingBrief = true

        let startDate = inferredStartDate()
        let durationDays = inferredDurationDays()
        let endDate = Calendar.current.date(byAdding: .day, value: max(durationDays - 1, 0), to: startDate) ?? startDate
        let people = inferredPeople()
        let budget = inferredBudgetTotal()
        let transport = inferredTransportType()

        let distanceKm = TravelDistanceCalculator.distanceKm(
            from: TravelDistanceCalculator.homeCoordinate(from: profile),
            to: (destination.latitude, destination.longitude)
        )
        destination.distanceKm = distanceKm

        let co2 = bootstrap.co2Estimator.estimate(
            distanceKm: distanceKm,
            transportType: transport,
            people: people
        )

        let trip = Trip(
            userId: profile.id,
            destinationId: destination.id,
            startDate: startDate,
            endDate: endDate,
            transportType: transport,
            people: people,
            budgetSpent: min(max(budget, 200), profile.budgetMax),
            co2Estimated: co2,
            ecoScoreSnapshot: destination.ecoScore
        )
        context.insert(trip)

        let encodedReport = encodedFinalReport(report)
        var persistedActivities: [ActivityItem] = []

        let briefItem = ActivityItem(
            tripId: trip.id,
            type: .brief,
            title: report.headline,
            note: report.overview,
            metaJSON: encodedReport
        )
        context.insert(briefItem)
        persistedActivities.append(briefItem)

        for attraction in report.attractions.prefix(8) {
            let item = ActivityItem(
                tripId: trip.id,
                type: .activity,
                title: attraction.name,
                note: "Best: \(attraction.bestTime) • Cost: \(attraction.estimatedCost) • \(attraction.why)"
            )
            context.insert(item)
            persistedActivities.append(item)
        }

        for highlight in report.dailyHighlights.prefix(5) {
            let item = ActivityItem(
                tripId: trip.id,
                type: .activity,
                title: highlight.day,
                note: "AM \(highlight.morning) | PM \(highlight.afternoon) | EVE \(highlight.evening) | Rain \(highlight.rainFallback)"
            )
            context.insert(item)
            persistedActivities.append(item)
        }

        for (index, line) in report.checklist.prefix(6).enumerated() {
            let item = ActivityItem(
                tripId: trip.id,
                type: .activity,
                title: "Checklist \(index + 1)",
                note: line
            )
            context.insert(item)
            persistedActivities.append(item)
        }

        bootstrap.syncManager.enqueue(
            type: .createTrip,
            payload: [
                "tripId": trip.id.uuidString,
                "userId": trip.userId.uuidString,
                "destinationId": destination.id.uuidString,
                "startDate": ISO8601DateFormatter().string(from: trip.startDate),
                "endDate": ISO8601DateFormatter().string(from: trip.endDate),
                "transportType": trip.transportType.rawValue,
                "people": "\(trip.people)",
                "budgetSpent": String(format: "%.0f", trip.budgetSpent),
                "co2Estimated": String(format: "%.2f", trip.co2Estimated),
                "ecoScoreSnapshot": String(format: "%.4f", trip.ecoScoreSnapshot),
                "destinationName": destination.name,
                "destinationCountry": destination.country,
                "destinationLatitude": String(format: "%.6f", destination.latitude),
                "destinationLongitude": String(format: "%.6f", destination.longitude),
                "destinationDistanceKm": String(format: "%.3f", destination.distanceKm),
                "destinationEcoScore": String(format: "%.3f", destination.ecoScore),
                "destinationClimate": destination.climate,
                "destinationCostIndex": String(format: "%.3f", destination.costIndex),
                "destinationCrowdingIndex": String(format: "%.3f", destination.crowdingIndex),
                "destinationStylesJSON": CodableStorage.encode(destination.styles, fallback: "[]"),
                "destinationTypicalSeasonJSON": CodableStorage.encode(destination.typicalSeason, fallback: "[]")
            ],
            context: context
        )

        for activity in persistedActivities {
            bootstrap.syncManager.enqueue(
                type: .saveActivities,
                payload: [
                    "activityId": activity.id.uuidString,
                    "tripId": trip.id.uuidString,
                    "type": activity.type.rawValue,
                    "title": activity.title,
                    "note": activity.note,
                    "metaJSON": activity.metaJSON ?? ""
                ],
                context: context
            )
        }

        do {
            try context.save()
            persistedConversation?.linkedTripId = trip.id
            saveConversationSnapshotIfPossible()
            homeViewModel.load(context: context, bootstrap: bootstrap)
            messages.append(.init(sender: .assistant, text: "Final Trip Brief saved to My Plan. I created the trip and persisted attractions/checklist as activities."))
        } catch {
            messages.append(.init(sender: .assistant, text: "Save failed. I could not persist the final brief in local storage."))
        }

        isPersistingBrief = false
        saveConversationSnapshotIfPossible()
    }

    private func initializeConversation() {
        messages = [
            PlannerChatMessage(
                sender: .assistant,
                text: "Planner Studio active. We will build your trip with a guided canvas: season, days, people, budget, interests, transportation, and activities."
            )
        ]

        if let firstQuestion = questionSteps.first {
            messages.append(.init(sender: .assistant, text: questionPrompt(for: firstQuestion)))
        }
        saveConversationSnapshotIfPossible()
    }

    private func acceptGuidedAnswer(_ answer: String, service: any OpenAIChatServing) async {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let question = currentQuestion else {
            await sendToAssistant(userText: trimmed, service: service)
            return
        }

        let inferredAnswers = inferGuidedAnswers(from: trimmed)
        let normalizedCurrentAnswer = normalizedGuidedAnswer(
            trimmed,
            for: question.key,
            inferredAnswers: inferredAnswers
        )

        messages.append(.init(sender: .user, text: trimmed))
        answers[question.key] = normalizedCurrentAnswer

        var autoFilledItems: [(PlannerQuestionStep.Key, String)] = []
        for step in questionSteps {
            let key = step.key
            guard key != question.key else { continue }
            guard answers[key] == nil else { continue }
            guard let inferred = inferredAnswers[key], !inferred.isEmpty else { continue }
            answers[key] = inferred
            autoFilledItems.append((key, inferred))
        }

        messages.append(.init(sender: .assistant, text: acknowledgement(for: question, answer: normalizedCurrentAnswer)))

        if !autoFilledItems.isEmpty {
            messages.append(.init(sender: .assistant, text: autoFillAcknowledgement(for: autoFilledItems)))
        }

        currentStepIndex += 1
        advanceToNextUnansweredStep()

        if let nextQuestion = currentQuestion {
            messages.append(.init(sender: .assistant, text: questionPrompt(for: nextQuestion)))
            saveConversationSnapshotIfPossible()
            return
        }

        stage = .generating
        messages.append(.init(sender: .assistant, text: "Perfect. I will now create your personalized planner using the full schema."))
        await requestPlanSuggestions(service: service)
        saveConversationSnapshotIfPossible()
    }

    private func requestPlanSuggestions(service: any OpenAIChatServing) async {
        isSending = true
        errorMessage = nil
        let assistantMessageID = appendAssistantPlaceholder()

        do {
            let prompt = buildPlannerPrompt()
            let reply = try await service.stream(
                userMessage: prompt,
                previousResponseID: previousResponseID
            ) { delta in
                await MainActor.run {
                    self.appendDelta(delta, to: assistantMessageID)
                }
            }
            previousResponseID = reply.responseID
            finalizeAssistantMessage(id: assistantMessageID, fallbackText: reply.text)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            finalizeAssistantMessage(id: assistantMessageID, fallbackText: offlineFallbackReasoning(errorMessage: message))
        }

        isSending = false
        stage = .freeform

        if !hasAutoGeneratedFinalReport {
            await generateFinalReport(service: service, isManualRequest: false)
        }
        saveConversationSnapshotIfPossible()
    }

    private func sendToAssistant(userText: String, service: any OpenAIChatServing) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if shouldBlockAsNonTravelRequest(trimmed) {
            messages.append(.init(sender: .user, text: trimmed))
            messages.append(.init(sender: .assistant, text: travelScopeGuardrailMessage()))
            saveConversationSnapshotIfPossible()
            return
        }

        let payload = composeFollowUpPrompt(userText: trimmed)
        await sendToAssistant(displayText: trimmed, payload: payload, service: service)
    }

    private func sendToAssistant(
        displayText: String,
        payload: String,
        service: any OpenAIChatServing
    ) async {
        let visibleText = displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visibleText.isEmpty else { return }

        messages.append(.init(sender: .user, text: visibleText))
        isSending = true
        errorMessage = nil
        let assistantMessageID = appendAssistantPlaceholder()

        do {
            let reply = try await service.stream(
                userMessage: payload,
                previousResponseID: previousResponseID
            ) { delta in
                await MainActor.run {
                    self.appendDelta(delta, to: assistantMessageID)
                }
            }
            previousResponseID = reply.responseID
            finalizeAssistantMessage(id: assistantMessageID, fallbackText: reply.text)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            finalizeAssistantMessage(
                id: assistantMessageID,
                fallbackText: "I cannot contact the AI service right now. \(message)"
            )
        }

        isSending = false
        saveConversationSnapshotIfPossible()
    }

    private func appendAssistantPlaceholder() -> UUID {
        let id = UUID()
        messages.append(
            PlannerChatMessage(
                id: id,
                sender: .assistant,
                text: "",
                createdAt: .now
            )
        )
        return id
    }

    private func appendDelta(_ delta: String, to messageID: UUID) {
        guard !delta.isEmpty else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        let current = messages[index]
        messages[index] = PlannerChatMessage(
            id: current.id,
            sender: current.sender,
            text: current.text + delta,
            createdAt: current.createdAt
        )
    }

    private func finalizeAssistantMessage(id messageID: UUID, fallbackText: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            messages.append(.init(sender: .assistant, text: fallbackText))
            return
        }

        let current = messages[index]
        let normalizedCurrent = current.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedCurrent.isEmpty {
            messages[index] = PlannerChatMessage(
                id: current.id,
                sender: .assistant,
                text: fallbackText,
                createdAt: current.createdAt
            )
        }
    }

    private func composeFollowUpPrompt(userText: String) -> String {
        guard !answers.isEmpty else { return userText }

        var lines: [String] = [
            "Planner context already collected:",
            formattedAnswers(),
            "",
            "User follow-up request:",
            userText,
            "",
            "Respond in the user's language with concise and practical recommendations consistent with this context.",
            "Format the response in polished Markdown with headings, bullet points, and compact sections."
        ]

        if stage == .guided {
            lines.append("We are still in guided mode, ask exactly one next useful question.")
        }

        return lines.joined(separator: "\n")
    }

    private func attractionInfoKey(for attractionName: String) -> String {
        let destination = answers[.destination] ?? ""
        let normalizedName = attractionName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDestination = destination
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedName)|\(normalizedDestination)"
    }

    private func shouldBlockAsNonTravelRequest(_ text: String) -> Bool {
        guard stage != .guided else { return false }

        let normalized = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return false }
        if Self.shortAllowedReplies.contains(normalized) { return false }

        if Self.travelKeywordHints.contains(where: { normalized.contains($0) }) {
            return false
        }

        if normalized.range(of: #"\b(day|days|giorno|giorni|week|settimana|km|€|\$)\b"#, options: .regularExpression) != nil {
            return false
        }

        let hasHardOffTopicHint = Self.nonTravelHardBlockHints.contains(where: { normalized.contains($0) })
        if !hasHardOffTopicHint {
            // Default permissive mode: avoid blocking valid travel follow-ups.
            return false
        }

        return true
    }

    private func travelScopeGuardrailMessage() -> String {
        """
        I can only help with travel planning.

        We can discuss destinations, itineraries, attractions, budgets, transport, hotels, restaurants, and logistics.
        Send me a travel-related request and I'll continue right away.
        """
    }

    private func questionPrompt(for question: PlannerQuestionStep) -> String {
        let number = (questionSteps.firstIndex(of: question) ?? 0) + 1
        return "[\(number)/\(questionSteps.count)] \(question.title)\n\(question.subtitle)"
    }

    private func advanceToNextUnansweredStep() {
        while currentStepIndex < questionSteps.count {
            let key = questionSteps[currentStepIndex].key
            if answers[key] == nil {
                break
            }
            currentStepIndex += 1
        }
    }

    private func acknowledgement(for question: PlannerQuestionStep, answer: String) -> String {
        switch question.key {
        case .destination:
            return "Great starting point: \(answer)."
        case .seasonAndDates:
            return "Timing recorded: \(answer)."
        case .freeDays:
            return "Trip duration saved: \(answer)."
        case .travelers:
            return "Group setup saved: \(answer)."
        case .travelersProfile:
            return "Age and relationship profile noted: \(answer)."
        case .budget:
            return "Budget range set to \(answer)."
        case .interests:
            return "Interests saved: \(answer)."
        case .transportation:
            return "Transportation preference set: \(answer)."
        case .activities:
            return "Activity pace selected: \(answer)."
        }
    }

    private func inferGuidedAnswers(from text: String) -> [PlannerQuestionStep.Key: String] {
        let normalized = normalizedInput(text)
        var inferred: [PlannerQuestionStep.Key: String] = [:]

        if let destination = extractDestination(from: text) {
            inferred[.destination] = destination
        }

        if let seasonAndDates = extractSeasonAndDates(fromNormalized: normalized, original: text) {
            inferred[.seasonAndDates] = seasonAndDates
        }

        if let freeDays = extractFreeDays(fromNormalized: normalized, original: text) {
            inferred[.freeDays] = freeDays
        }

        if let travelers = extractTravelers(fromNormalized: normalized) {
            inferred[.travelers] = travelers
        }

        if let travelersProfile = extractTravelersProfile(fromNormalized: normalized) {
            inferred[.travelersProfile] = travelersProfile
        }

        if let budget = extractBudget(fromNormalized: normalized, original: text) {
            inferred[.budget] = budget
        }

        if let interests = extractInterests(fromNormalized: normalized) {
            inferred[.interests] = interests
        }

        if let transportation = extractTransportation(fromNormalized: normalized) {
            inferred[.transportation] = transportation
        }

        if let activities = extractActivitiesPace(fromNormalized: normalized) {
            inferred[.activities] = activities
        }

        return inferred
    }

    private func normalizedGuidedAnswer(
        _ raw: String,
        for key: PlannerQuestionStep.Key,
        inferredAnswers: [PlannerQuestionStep.Key: String]
    ) -> String {
        if let inferred = inferredAnswers[key], !inferred.isEmpty {
            return inferred
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func autoFillAcknowledgement(for items: [(PlannerQuestionStep.Key, String)]) -> String {
        guard !items.isEmpty else { return "" }

        let ordered = questionSteps.compactMap { step -> (PlannerQuestionStep.Key, String)? in
            items.first(where: { $0.0 == step.key })
        }
        let lines = ordered.map { "- \(shortLabel(for: $0.0)): \($0.1)" }

        return """
        I auto-filled these fields from your message:
        \(lines.joined(separator: "\n"))
        """
    }

    private func normalizedInput(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractDestination(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"(?:voglio|vorrei|mi piacerebbe)\s+(?:andare|visitare|fare\s+un\s+viaggio)\s+(?:a|in)\s+([^,\.\!\?\n]+)"#,
            #"(?:vado|andiamo|andr[oò])\s+(?:a|in)\s+([^,\.\!\?\n]+)"#,
            #"(?:go|going|travel|trip|visit)(?:\s+to)?\s+([^,\.\!\?\n]+)"#,
            #"(?:destination|destinazione)\s*[:\-]\s*([^,\.\!\?\n]+)"#
        ]

        for pattern in patterns {
            if let capture = firstCapture(in: trimmed, pattern: pattern),
               let cleaned = cleanDestinationCandidate(capture) {
                return cleaned
            }
        }

        if let cleaned = cleanDestinationCandidate(trimmed) {
            return cleaned
        }
        return nil
    }

    private func cleanDestinationCandidate(_ candidate: String) -> String? {
        var value = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[:\-\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let stopMarkers = [
            " con ", " with ", " per ", " for ", " budget", " questo ", " questa ", " next ",
            " in primavera", " in estate", " in autunno", " in inverno",
            " in spring", " in summer", " in autumn", " in winter",
            " per ", " perche ", " perché ", " dal ", " from "
        ]

        let lowered = normalizedInput(value)
        var stopIndex: String.Index?
        for marker in stopMarkers {
            if let range = lowered.range(of: marker) {
                if stopIndex == nil || range.lowerBound < stopIndex! {
                    stopIndex = range.lowerBound
                }
            }
        }

        if let stopIndex {
            let distance = lowered.distance(from: lowered.startIndex, to: stopIndex)
            let originalStopIndex = value.index(value.startIndex, offsetBy: min(distance, value.count))
            value = String(value[..<originalStopIndex])
        }

        value = value
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;!?\"'()[]{}"))
            .replacingOccurrences(of: #"^(?:voglio|vorrei|mi piacerebbe|andare|visitare|go|travel|trip|destination|destinazione)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !value.isEmpty else { return nil }
        guard value.count >= 2, value.count <= 52 else { return nil }

        let loweredValue = normalizedInput(value)
        let blocked = [
            "budget", "giorni", "days", "people", "persone", "weekend", "settimana", "travel", "trip",
            "solo", "couple", "coppia", "family", "famiglia", "friends", "amici",
            "spring", "summer", "autumn", "winter", "primavera", "estate", "autunno", "inverno"
        ]
        if blocked.contains(where: { loweredValue == $0 }) {
            return nil
        }

        if loweredValue == "anywhere" || loweredValue == "ovunque" {
            return "Anywhere"
        }

        return value.localizedCapitalized
    }

    private func extractSeasonAndDates(fromNormalized text: String, original: String) -> String? {
        if text.contains("flexible") || text.contains("flessib") {
            return "Flexible dates"
        }
        if text.contains("spring") || text.contains("primavera") {
            return "Spring"
        }
        if text.contains("summer") || text.contains("estate") {
            return "Summer"
        }
        if text.contains("autumn") || text.contains("fall") || text.contains("autunno") {
            return "Autumn"
        }
        if text.contains("winter") || text.contains("inverno") {
            return "Winter"
        }

        if let match = firstCapture(in: original, pattern: #"((?:early|late|inizio|fine)?\s*(?:jan|feb|mar|apr|mag|giu|lug|ago|set|ott|nov|dic|january|february|march|april|may|june|july|august|september|october|november|december)[^\n,]*)"#) {
            let cleaned = match.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }

        return nil
    }

    private func extractFreeDays(fromNormalized text: String, original: String) -> String? {
        if text.contains("weekend") {
            return "Weekend"
        }

        if let match = firstCapture(in: text, pattern: #"(\d{1,2})\s*(?:giorni|giorno|days|day)\b"#),
           let days = Int(match), days > 0 {
            return "\(days) days"
        }

        if let match = firstCapture(in: text, pattern: #"(\d{1,2})\s*(?:settimane|settimana|weeks|week)\b"#),
           let weeks = Int(match), weeks > 0 {
            if weeks >= 2 { return "2+ weeks" }
            return "\(weeks) week"
        }

        if original.localizedCaseInsensitiveContains("4-6") { return "4-6 days" }
        if original.localizedCaseInsensitiveContains("7-10") { return "7-10 days" }
        if original.localizedCaseInsensitiveContains("2+ weeks") { return "2+ weeks" }
        return nil
    }

    private func extractTravelers(fromNormalized text: String) -> String? {
        if text.contains("solo") {
            return "Solo"
        }
        if text.contains("couple") || text.contains("coppia") {
            return "Couple"
        }
        if text.contains("family") || text.contains("famiglia") {
            return "Family"
        }
        if text.contains("friends") || text.contains("amici") {
            return "Friends group"
        }
        return nil
    }

    private func extractTravelersProfile(fromNormalized text: String) -> String? {
        if text.contains("children") || text.contains("kids") || text.contains("bambin") {
            return "With children"
        }
        if text.contains("mixed generations") || text.contains("multigeneraz") || text.contains("nonni") {
            return "Mixed generations"
        }
        if text.contains("very flexible") || text.contains("molto fless") {
            return "Very flexible"
        }
        if text.contains("adults only") || text.contains("solo adult") {
            return "Adults only"
        }
        return nil
    }

    private func extractBudget(fromNormalized text: String, original: String) -> String? {
        if text.contains("smart") {
            return "Smart"
        }
        if text.contains("comfort") {
            return "Comfort"
        }
        if text.contains("premium") {
            return "Premium"
        }
        if text.contains("luxury") || text.contains("lusso") {
            return "Luxury"
        }

        if let amount = firstCapture(in: text, pattern: #"(\d{3,6})\s*(?:€|eur|euro|\$|usd)\b"#) {
            return "\(amount) EUR total"
        }

        if let amount = firstCapture(
            in: original,
            pattern: #"(?:budget|totale|total|spesa|spend)[^\d]{0,12}(\d{3,6})"#
        ) {
            return "\(amount) EUR total"
        }

        return nil
    }

    private func extractInterests(fromNormalized text: String) -> String? {
        var picks: [String] = []
        if text.contains("food") || text.contains("cibo") || text.contains("gastron") {
            picks.append("Food")
        }
        if text.contains("culture") || text.contains("cultura") || text.contains("museum") || text.contains("muse") {
            picks.append("Culture")
        }
        if text.contains("nature") || text.contains("natura") {
            picks.append("Nature")
        }
        if text.contains("adventure") || text.contains("avventura") {
            picks.append("Adventure")
        }
        guard !picks.isEmpty else { return nil }
        return picks.joined(separator: " + ")
    }

    private func extractTransportation(fromNormalized text: String) -> String? {
        if text.contains("metro") || text.contains("walking") || text.contains("walk") || text.contains("cammino") {
            return "Metro + walking"
        }
        if text.contains("rental car") || text.contains("car") || text.contains("auto") {
            return "Rental car"
        }
        if text.contains("train") || text.contains("treni") || text.contains("treno") {
            return "Trains"
        }
        if text.contains("mixed") || text.contains("misto") {
            return "Mixed"
        }
        return nil
    }

    private func extractActivitiesPace(fromNormalized text: String) -> String? {
        if text.contains("relaxed") || text.contains("rilassat") {
            return "Relaxed"
        }
        if text.contains("balanced") || text.contains("bilanciat") {
            return "Balanced"
        }
        if text.contains("full immersion") || text.contains("immersione totale") {
            return "Full immersion"
        }
        if text.contains("nightlife") || text.contains("vita notturna") {
            return "Nightlife"
        }
        return nil
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let fullRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: fullRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildPlannerPrompt() -> String {
        """
        You are a senior travel strategist creating a real planner.

        Use this planning schema from the UI:
        - Weather/season + date flexibility
        - Free days
        - People + age/relationship + flexibility
        - Budget
        - Interests
        - Transportation preferences
        - Activities rhythm

        User profile:
        \(formattedAnswers())

        Produce the best possible travel plan in the user's language with this exact structure:
        1) Concept overview (2-3 lines)
        2) Destination strategy (primary + one backup option)
        3) Day-by-day planner with Morning / Afternoon / Evening blocks
        4) Budget split (transport, stay, food, activities, buffer)
        5) Transport recommendations with tradeoffs
        6) Top activities with one rainy-day fallback for each day
        7) Booking checklist sorted by urgency
        8) 5 highly specific smart tips tailored to this profile

        Keep it concrete, realistic, and easy to execute.
        Output the result in polished Markdown with clear section headings and bullet points.
        """
    }

    private func actionPrompt(for action: PlannerSmartAction) -> String {
        let destination = answers[.destination] ?? "chosen destination"
        let context = formattedAnswers()

        switch action {
        case .attractions:
            return """
            Planner context:
            \(context)

            Request: Create 10 specific attractions for \(destination), grouped by area, with estimated visit duration and best time slot.
            Respond in the user's language using polished Markdown with concise bullet points.
            """
        case .hiddenGems:
            return """
            Planner context:
            \(context)

            Request: Provide 7 hidden gems in \(destination) that tourists often miss, each with why it is worth it and a practical access tip.
            Respond in the user's language using polished Markdown.
            """
        case .foodSpots:
            return """
            Planner context:
            \(context)

            Request: Build a food map for \(destination) with 8 spots (breakfast, lunch, dinner, dessert, market), budget level, and what to order.
            Respond in the user's language using polished Markdown.
            """
        case .familyFriendly:
            return """
            Planner context:
            \(context)

            Request: Adapt the plan for family-friendly execution with kid-friendly attractions, transfer limits, break windows, and safety notes.
            Respond in the user's language using polished Markdown.
            """
        case .optimizeBudget:
            return """
            Planner context:
            \(context)

            Request: Optimize this trip budget with concrete savings opportunities and what not to downgrade.
            Return a before/after mini table in Markdown.
            """
        case .transportTactics:
            return """
            Planner context:
            \(context)

            Request: Suggest the smartest transportation strategy for \(destination), including passes, airport transfers, and time-saving combinations.
            Keep tradeoffs explicit and concise.
            Respond in polished Markdown.
            """
        case .rainyBackup:
            return """
            Planner context:
            \(context)

            Request: Create a rainy-day backup version of the itinerary with indoor alternatives for each day and relocation time estimates.
            Respond in polished Markdown.
            """
        case .bookingTimeline:
            return """
            Planner context:
            \(context)

            Request: Build a booking timeline with deadlines: book now, book this week, and book later.
            Include risk level for each line.
            Respond in polished Markdown.
            """
        case .finalizeBrief, .refreshBrief:
            return ""
        }
    }

    private func shouldGenerateFinalReport(for text: String) -> Bool {
        let lowered = text.lowercased()
        let keywords = [
            "resoconto",
            "riepilogo",
            "recap",
            "summary",
            "final report",
            "finalizza",
            "finale"
        ]
        return keywords.contains { lowered.contains($0) }
    }

    private func generateFinalReport(
        service: any OpenAIChatServing,
        isManualRequest: Bool
    ) async {
        guard !isGeneratingFinalReport else { return }

        isGeneratingFinalReport = true
        errorMessage = nil

        if isManualRequest {
            messages.append(.init(sender: .assistant, text: "Generating your final trip brief with attractions, logistics, and checklist."))
        }

        let rankedLiveAttractions = await fetchRankedLiveAttractions(limit: 8)

        if let localReport = await generateLocalFinalReportIfAvailable(liveAttractions: rankedLiveAttractions) {
            finalReport = mergeLiveAttractions(into: localReport, liveAttractions: rankedLiveAttractions)
            hasAutoGeneratedFinalReport = true
            messages.append(.init(sender: .assistant, text: "Final Trip Brief ready below (generated on-device)."))
            isGeneratingFinalReport = false
            return
        }

        do {
            let reply = try await service.send(
                userMessage: buildFinalReportPrompt(liveAttractions: rankedLiveAttractions),
                previousResponseID: previousResponseID
            )
            previousResponseID = reply.responseID

            if let report = decodeFinalReport(from: reply.text) {
                finalReport = mergeLiveAttractions(into: report, liveAttractions: rankedLiveAttractions)
                hasAutoGeneratedFinalReport = true
                messages.append(.init(sender: .assistant, text: "Final Trip Brief ready below. You can refresh it anytime from Agent Actions."))
            } else {
                finalReport = offlineFallbackFinalReport(liveAttractions: rankedLiveAttractions)
                hasAutoGeneratedFinalReport = true
                messages.append(.init(sender: .assistant, text: "I generated the brief from your planner context."))
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            finalReport = offlineFallbackFinalReport(liveAttractions: rankedLiveAttractions)
            hasAutoGeneratedFinalReport = true
            messages.append(.init(sender: .assistant, text: "I could not reach the AI endpoint, so I prepared an offline final brief. \(message)"))
        }

        isGeneratingFinalReport = false
        saveConversationSnapshotIfPossible()
    }

    private func generateLocalFinalReportIfAvailable(
        liveAttractions: [PlannerFinalAttraction]
    ) async -> PlannerFinalReport? {
#if canImport(FoundationModels)
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: buildFinalReportPrompt(liveAttractions: liveAttractions))
            let text = responseContent(from: response)
            return decodeFinalReport(from: text)
        } catch {
            return nil
        }
#else
        return nil
#endif
    }

    private func buildFinalReportPrompt(liveAttractions: [PlannerFinalAttraction]) -> String {
        let context = formattedAnswers()
        let latestAssistantMessages = messages
            .reversed()
            .filter { $0.sender == .assistant }
            .prefix(3)
            .map(\.text)
            .joined(separator: "\n\n")
        let liveAttractionsBlock = liveAttractions.isEmpty
            ? "No live attractions available."
            : liveAttractions.enumerated().map { index, item in
                "\(index + 1). \(item.name) | \(item.bestTime) | \(item.estimatedCost) | \(item.why)"
            }.joined(separator: "\n")

        return """
        You are the planner agent finalizer.
        Build an executive trip report from the collected context.

        Planner context:
        \(context)

        Latest planning outputs:
        \(latestAssistantMessages)

        Ranked live attractions (budget/interest weighted):
        \(liveAttractionsBlock)

        Return ONLY valid JSON with this exact shape:
        {
          "headline": "string",
          "overview": "string",
          "destinationFocus": "string",
          "bestTravelWindow": "string",
          "budgetSnapshot": "string",
          "transportStrategy": "string",
          "attractions": [
            {"name": "string", "why": "string", "bestTime": "string", "estimatedCost": "string"}
          ],
          "dailyHighlights": [
            {"day": "Day 1", "morning": "string", "afternoon": "string", "evening": "string", "rainFallback": "string"}
          ],
          "checklist": ["string"],
          "notes": ["string"]
        }

        Constraints:
        - language: match the user language from context
        - attractions: 6 to 10
        - dailyHighlights: 3 to 7
        - checklist: 12 to 16 concise actionable lines
        - notes: 8 to 12 risk/awareness lines
        - "overview": include strategic context (best zones, practical style, why this plan fits profile, and crowd-avoidance logic)
        - "transportStrategy": include airport transfer, city pass suggestion, when to use taxi vs transit, and late-night fallback
        - each attraction "why" must include: practical reason + expected duration + booking note + nearest transit hint + one local tip
        - each dailyHighlights block must include concrete timing guidance and transfer logic between slots
        - checklist lines must be operational and prioritized (book now / this week / later)
        - notes must include safety, weather, closure/holiday risk, budget variance reminders, and scam-avoidance tips
        - no markdown, no prose before or after JSON
        """
    }

    private func decodeFinalReport(from raw: String) -> PlannerFinalReport? {
        let candidates = [raw, extractJSONObject(from: raw)].compactMap { $0 }
        let decoder = JSONDecoder()

        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let parsed = try? decoder.decode(PlannerFinalReportDTO.self, from: data) else { continue }

            let attractions = parsed.attractions
                .prefix(10)
                .map {
                    PlannerFinalAttraction(
                        name: cleanedText($0.name),
                        why: cleanedText($0.why),
                        bestTime: cleanedText($0.bestTime),
                        estimatedCost: cleanedText($0.estimatedCost)
                    )
                }

            let highlights = parsed.dailyHighlights
                .prefix(7)
                .map {
                    PlannerDayHighlight(
                        day: cleanedText($0.day),
                        morning: cleanedText($0.morning),
                        afternoon: cleanedText($0.afternoon),
                        evening: cleanedText($0.evening),
                        rainFallback: cleanedText($0.rainFallback)
                    )
                }

            let checklist = parsed.checklist.map(cleanedText).filter { !$0.isEmpty }
            let notes = parsed.notes.map(cleanedText).filter { !$0.isEmpty }

            guard !cleanedText(parsed.headline).isEmpty else { continue }

            return PlannerFinalReport(
                headline: cleanedText(parsed.headline),
                overview: cleanedText(parsed.overview),
                destinationFocus: cleanedText(parsed.destinationFocus),
                bestTravelWindow: cleanedText(parsed.bestTravelWindow),
                budgetSnapshot: cleanedText(parsed.budgetSnapshot),
                transportStrategy: cleanedText(parsed.transportStrategy),
                attractions: attractions.isEmpty ? fallbackAttractions() : attractions,
                dailyHighlights: highlights.isEmpty ? fallbackHighlights() : highlights,
                checklist: checklist.isEmpty ? fallbackChecklist() : checklist,
                notes: notes.isEmpty ? fallbackNotes() : notes,
                generatedAt: .now
            )
        }

        return nil
    }

    private func mergeLiveAttractions(
        into report: PlannerFinalReport,
        liveAttractions: [PlannerFinalAttraction]
    ) -> PlannerFinalReport {
        guard !liveAttractions.isEmpty else { return report }
        var seen = Set<String>()
        var merged: [PlannerFinalAttraction] = []

        for item in liveAttractions + report.attractions {
            let key = PlaceCanonicalizer.normalizeText(item.name)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(item)
            if merged.count >= 10 { break }
        }

        return PlannerFinalReport(
            headline: report.headline,
            overview: report.overview,
            destinationFocus: report.destinationFocus,
            bestTravelWindow: report.bestTravelWindow,
            budgetSnapshot: report.budgetSnapshot,
            transportStrategy: report.transportStrategy,
            attractions: merged,
            dailyHighlights: report.dailyHighlights,
            checklist: report.checklist,
            notes: report.notes,
            generatedAt: report.generatedAt
        )
    }

    private func offlineFallbackFinalReport(
        liveAttractions: [PlannerFinalAttraction]
    ) -> PlannerFinalReport {
        let destination = answers[.destination] ?? "Your destination"
        let season = answers[.seasonAndDates] ?? "Flexible dates"
        let budget = answers[.budget] ?? "Budget not specified"
        let transport = answers[.transportation] ?? "Mixed transport"
        let interests = answers[.interests] ?? "Culture + Food"

        let attractions = liveAttractions.isEmpty ? fallbackAttractions() : Array(liveAttractions.prefix(10))

        return PlannerFinalReport(
            headline: "Final Trip Brief • \(destination)",
            overview: "Trip profile built around \(interests), with pacing optimized for practical execution and backup options.",
            destinationFocus: destination,
            bestTravelWindow: season,
            budgetSnapshot: budget,
            transportStrategy: transport,
            attractions: attractions,
            dailyHighlights: fallbackHighlights(),
            checklist: fallbackChecklist(),
            notes: fallbackNotes(),
            generatedAt: .now
        )
    }

    private func fetchRankedLiveAttractions(limit: Int) async -> [PlannerFinalAttraction] {
        guard let provider = liveActivitiesSearchProvider else { return [] }

        let input = SearchInput(
            query: [answers[.destination], answers[.interests], answers[.activities]]
                .compactMap { $0 }
                .joined(separator: " "),
            budget: inferredBudgetTotal(),
            people: inferredPeople(),
            startDate: inferredStartDate(),
            endDate: Calendar.current.date(byAdding: .day, value: max(inferredDurationDays() - 1, 0), to: inferredStartDate()) ?? inferredStartDate(),
            destinationName: answers[.destination],
            destinationCountry: nil,
            latitude: nil,
            longitude: nil
        )

        let live = await provider(input)
        guard !live.isEmpty else { return [] }

        let interestTokens = parseInterestTokens()
        let targetBudgetPerActivity = max(18, inferredBudgetTotal() / max(Double(inferredDurationDays()), 1) / 2.0)

        let ranked = live
            .map { option -> (ActivityOption, Double) in
                let titleAndCategory = "\(option.title) \(option.category)".lowercased()
                let keywordHits = interestTokens.filter { titleAndCategory.contains($0) }.count
                let interestScore = interestTokens.isEmpty
                    ? 0.45
                    : min(1.0, Double(keywordHits) / Double(max(interestTokens.count, 1)) + 0.2)

                let budgetDelta = abs(option.estimatedCost - targetBudgetPerActivity)
                let budgetScore = max(0.05, 1 - (budgetDelta / max(targetBudgetPerActivity, 20)))

                let categoryBoost: Double = titleAndCategory.contains("museum")
                    || titleAndCategory.contains("historic")
                    || titleAndCategory.contains("food")
                    ? 0.12
                    : 0

                let score = (interestScore * 0.56) + (budgetScore * 0.36) + categoryBoost
                return (option, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.estimatedCost < rhs.0.estimatedCost
                }
                return lhs.1 > rhs.1
            }
            .prefix(limit)

        return ranked.map { option, score in
            PlannerFinalAttraction(
                name: option.title,
                why: "Live ranked \(String(format: "%.2f", score)) • \(readableCategory(option.category)) • aligned with your interests and budget.",
                bestTime: preferredTimeSlot(for: option.category),
                estimatedCost: "€\(Int(option.estimatedCost))"
            )
        }
    }

    private func fallbackAttractions() -> [PlannerFinalAttraction] {
        let destination = answers[.destination] ?? "destination"
        let interests = answers[.interests] ?? "culture and food"

        return [
            PlannerFinalAttraction(
                name: "Historic center walk",
                why: "Best orientation of \(destination) with architecture and local rhythm.",
                bestTime: "Morning",
                estimatedCost: "Low"
            ),
            PlannerFinalAttraction(
                name: "Signature museum district",
                why: "High concentration of key landmarks aligned with \(interests).",
                bestTime: "Late morning",
                estimatedCost: "Medium"
            ),
            PlannerFinalAttraction(
                name: "Local market + food court",
                why: "Efficient way to taste local specialties and compare prices.",
                bestTime: "Lunch",
                estimatedCost: "Low to medium"
            ),
            PlannerFinalAttraction(
                name: "Sunset viewpoint",
                why: "Low-effort high-impact slot for photos and atmosphere.",
                bestTime: "Sunset",
                estimatedCost: "Free"
            ),
            PlannerFinalAttraction(
                name: "Neighborhood evening loop",
                why: "Adds authentic local life outside peak tourist zones.",
                bestTime: "Evening",
                estimatedCost: "Low"
            ),
            PlannerFinalAttraction(
                name: "Rain-proof cultural venue",
                why: "Protects itinerary quality with indoor fallback.",
                bestTime: "Anytime",
                estimatedCost: "Medium"
            )
        ]
    }

    private func fallbackHighlights() -> [PlannerDayHighlight] {
        [
            PlannerDayHighlight(
                day: "Day 1",
                morning: "Arrival, hotel check-in, and orientation walk.",
                afternoon: "Historic district and first anchor attraction.",
                evening: "Local dinner area and relaxed stroll.",
                rainFallback: "Indoor museum cluster near city center."
            ),
            PlannerDayHighlight(
                day: "Day 2",
                morning: "Top landmark before crowds.",
                afternoon: "Food market and neighborhood exploration.",
                evening: "Viewpoint + signature dinner booking.",
                rainFallback: "Culinary workshop or covered market route."
            ),
            PlannerDayHighlight(
                day: "Day 3",
                morning: "Secondary attractions or day-trip module.",
                afternoon: "Shopping and flexible buffer block.",
                evening: "Last night highlights and packing window.",
                rainFallback: "Design galleries and café crawl."
            )
        ]
    }

    private func fallbackChecklist() -> [String] {
        [
            "Lock transport first, then hotel cancellation-safe option.",
            "Prebook top 2 attractions with timed entry.",
            "Reserve one high-value dinner in advance.",
            "Prepare offline map + emergency meeting point.",
            "Keep 12-15% budget as contingency buffer.",
            "Create one indoor backup per day."
        ]
    }

    private func fallbackNotes() -> [String] {
        [
            "Peak-hour queues can reduce daily throughput.",
            "Airport-city transfer time varies by traffic window.",
            "Weather volatility may require swapping day blocks."
        ]
    }

    private func extractJSONObject(from text: String) -> String? {
        guard let first = text.firstIndex(of: "{"),
              let last = text.lastIndex(of: "}") else { return nil }
        guard first <= last else { return nil }
        return String(text[first...last])
    }

    private func cleanedText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
    }

    private func responseContent<T>(from response: T) -> String {
        let mirror = Mirror(reflecting: response)
        for child in mirror.children {
            guard child.label == "content" || child.label == "outputText" else { continue }
            if let text = child.value as? String {
                return text
            }
        }
        return String(describing: response)
    }

    private func resolveDestination(from rawDestination: String?, homeViewModel: HomeViewModel) -> Destination? {
        let query = PlaceCanonicalizer.normalizeText(rawDestination ?? "")
        if !query.isEmpty {
            if let exact = homeViewModel.destinations.first(where: {
                PlaceCanonicalizer.normalizeText($0.name) == query
                    || PlaceCanonicalizer.normalizeText("\($0.name), \($0.country)") == query
            }) {
                return exact
            }

            if let contains = homeViewModel.destinations.first(where: {
                let normalizedName = PlaceCanonicalizer.normalizeText($0.name)
                let normalizedCountry = PlaceCanonicalizer.normalizeText($0.country)
                return normalizedName.contains(query) || query.contains(normalizedName) || normalizedCountry.contains(query)
            }) {
                return contains
            }
        }

        if let recommended = homeViewModel.recommendations.first?.destination {
            return recommended
        }
        return homeViewModel.destinations.first
    }

    private func inferredStartDate() -> Date {
        Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    }

    private func inferredDurationDays() -> Int {
        let fallback = 5
        guard let value = answers[.freeDays]?.lowercased() else { return fallback }

        if value.contains("weekend") {
            return 2
        }
        if value.contains("2+ weeks") || value.contains("2 weeks") {
            return 14
        }
        if value.contains("7-10") {
            return 8
        }
        if value.contains("4-6") {
            return 5
        }

        if let parsed = firstNumericValue(in: value) {
            return max(2, min(Int(parsed.rounded()), 21))
        }
        return fallback
    }

    private func inferredPeople() -> Int {
        if let raw = answers[.travelers]?.lowercased() {
            if raw.contains("solo") { return 1 }
            if raw.contains("couple") { return 2 }
            if raw.contains("family") { return 3 }
            if raw.contains("friends") { return 4 }
            if let parsed = firstNumericValue(in: raw) {
                return max(1, min(Int(parsed.rounded()), 8))
            }
        }
        return 2
    }

    private func inferredBudgetTotal() -> Double {
        guard let rawBudget = answers[.budget]?.lowercased() else { return 2_200 }

        if rawBudget.contains("smart") { return 1_400 }
        if rawBudget.contains("comfort") { return 2_400 }
        if rawBudget.contains("premium") { return 4_100 }
        if rawBudget.contains("luxury") { return 6_200 }

        if let parsed = firstNumericValue(in: rawBudget) {
            return max(500, parsed)
        }
        return 2_200
    }

    private func inferredTransportType() -> TransportType {
        guard let raw = answers[.transportation]?.lowercased() else { return .plane }
        if raw.contains("train") || raw.contains("metro") || raw.contains("tram") {
            return .train
        }
        if raw.contains("car") || raw.contains("rental") {
            return .car
        }
        return .plane
    }

    private func parseInterestTokens() -> [String] {
        let base = answers[.interests]?.lowercased() ?? ""
        let rawTokens = base
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 2 }
        let unique = Array(Set(rawTokens)).sorted()
        return unique
    }

    private func firstNumericValue(in text: String) -> Double? {
        let pattern = #"\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range, in: text) else { return nil }
        var raw = String(text[valueRange])
        let digitCount = raw.filter(\.isNumber).count
        if raw.contains(",") && !raw.contains(".") && digitCount >= 4 {
            raw = raw.replacingOccurrences(of: ",", with: "")
        } else {
            raw = raw.replacingOccurrences(of: ",", with: ".")
        }
        return Double(raw)
    }

    private func readableCategory(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func preferredTimeSlot(for rawCategory: String) -> String {
        let category = rawCategory.lowercased()
        if category.contains("night") || category.contains("bar") {
            return "Evening"
        }
        if category.contains("museum") || category.contains("gallery") || category.contains("historic") {
            return "Morning"
        }
        if category.contains("park") || category.contains("nature") {
            return "Afternoon"
        }
        return "Late morning"
    }

    private func encodedFinalReport(_ report: PlannerFinalReport) -> String? {
        guard let data = try? JSONEncoder().encode(report),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private func loadConversationSnapshot(from conversation: PlannerConversation) -> Bool {
        guard let data = conversation.snapshotJSON.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(PlannerConversationSnapshot.self, from: data) else {
            return false
        }

        messages = snapshot.messages.isEmpty
            ? [PlannerChatMessage(sender: .assistant, text: "Planner Studio active. Continue from your previous session.")]
            : snapshot.messages
        answers = Dictionary(
            uniqueKeysWithValues: snapshot.answers.compactMap { key, value in
                guard let mappedKey = PlannerQuestionStep.Key(rawValue: key) else { return nil }
                return (mappedKey, value)
            }
        )
        currentStepIndex = snapshot.currentStepIndex
        stage = snapshot.stage
        finalReport = snapshot.finalReport
        previousResponseID = snapshot.previousResponseID
        hasAutofiredInitialPrompt = snapshot.hasAutofiredInitialPrompt
        hasAutoGeneratedFinalReport = snapshot.hasAutoGeneratedFinalReport
        isGeneratingFinalReport = false
        isPersistingBrief = false
        errorMessage = nil
        advanceToNextUnansweredStep()
        return true
    }

    private func saveConversationSnapshotIfPossible() {
        guard let context = modelContext,
              let conversation = persistedConversation else { return }

        let snapshot = PlannerConversationSnapshot(
            messages: messages,
            answers: answers.reduce(into: [:]) { partial, entry in
                partial[entry.key.rawValue] = entry.value
            },
            currentStepIndex: currentStepIndex,
            stage: stage,
            finalReport: finalReport,
            previousResponseID: previousResponseID,
            hasAutofiredInitialPrompt: hasAutofiredInitialPrompt,
            hasAutoGeneratedFinalReport: hasAutoGeneratedFinalReport
        )

        guard let encoded = try? JSONEncoder().encode(snapshot),
              let json = String(data: encoded, encoding: .utf8) else { return }

        conversation.snapshotJSON = json
        conversation.updatedAt = .now
        conversation.title = inferredConversationTitle()
        conversation.lastMessagePreview = messages.last?.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160).description ?? ""
        conversation.destinationHint = answers[.destination]
        conversation.hasFinalBrief = finalReport != nil
        conversation.finalBriefHeadline = finalReport?.headline
        conversation.finalBriefOverview = finalReport?.overview

        try? context.save()
    }

    private func inferredConversationTitle() -> String {
        if let destination = answers[.destination]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !destination.isEmpty,
           destination.caseInsensitiveCompare("anywhere") != .orderedSame {
            return "Trip • \(destination)"
        }

        if let firstUser = messages.first(where: { $0.sender == .user })?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !firstUser.isEmpty {
            return String(firstUser.prefix(42))
        }

        return "New chat"
    }

    private func formattedAnswers() -> String {
        questionSteps.map { step in
            let value = answers[step.key] ?? "Not provided"
            return "- \(shortLabel(for: step.key)): \(value)"
        }
        .joined(separator: "\n")
    }

    private func shortLabel(for key: PlannerQuestionStep.Key) -> String {
        switch key {
        case .destination:
            return "Destination"
        case .seasonAndDates:
            return "Season and dates"
        case .freeDays:
            return "Free days"
        case .travelers:
            return "People"
        case .travelersProfile:
            return "Age and relationship"
        case .budget:
            return "Budget"
        case .interests:
            return "Interests"
        case .transportation:
            return "Transportation"
        case .activities:
            return "Activities"
        }
    }

    private func offlineFallbackReasoning(errorMessage: String) -> String {
        """
        I could not reach the AI service, so here is a quick offline baseline built from your schema.

        \(formattedAnswers())

        Recommended next moves:
        1. Confirm destination and dates first, then lock transportation.
        2. Book priority activities in advance and keep a weather backup plan for each day.
        3. Keep 12-15% of your budget as a buffer for local transport and unexpected costs.

        Technical error: \(errorMessage)
        """
    }
}

private struct PlannerFinalReportDTO: Decodable {
    struct AttractionDTO: Decodable {
        let name: String
        let why: String
        let bestTime: String
        let estimatedCost: String
    }

    struct DayHighlightDTO: Decodable {
        let day: String
        let morning: String
        let afternoon: String
        let evening: String
        let rainFallback: String
    }

    let headline: String
    let overview: String
    let destinationFocus: String
    let bestTravelWindow: String
    let budgetSnapshot: String
    let transportStrategy: String
    let attractions: [AttractionDTO]
    let dailyHighlights: [DayHighlightDTO]
    let checklist: [String]
    let notes: [String]
}

private struct PlannerConversationSnapshot: Codable {
    let messages: [PlannerChatMessage]
    let answers: [String: String]
    let currentStepIndex: Int
    let stage: PlannerConversationStage
    let finalReport: PlannerFinalReport?
    let previousResponseID: String?
    let hasAutofiredInitialPrompt: Bool
    let hasAutoGeneratedFinalReport: Bool
}

private extension PlannerQuestionStep {
    static let flow: [PlannerQuestionStep] = [
        PlannerQuestionStep(
            key: .destination,
            title: "Where do you want to go?",
            subtitle: "Start from a destination or a travel style, even an open one.",
            icon: "location.fill",
            options: ["Moon", "New York", "Paris", "Anywhere"],
            placeholder: "Write a destination, an area, or a style...",
            skipValue: "Anywhere"
        ),
        PlannerQuestionStep(
            key: .seasonAndDates,
            title: "Season, dates, and flexibility",
            subtitle: "Weather impacts itinerary, costs, and activity quality.",
            icon: "cloud.sun.fill",
            options: ["Spring", "Summer", "Autumn", "Flexible dates"],
            placeholder: "Example: early June, +/- 3 days",
            skipValue: "Flexible dates"
        ),
        PlannerQuestionStep(
            key: .freeDays,
            title: "How many free days do you have?",
            subtitle: "We size the plan to avoid unnecessary rushing.",
            icon: "calendar.badge.clock",
            options: ["Weekend", "4-6 days", "7-10 days", "2+ weeks"],
            placeholder: "Example: 6 full days",
            skipValue: "4-6 days"
        ),
        PlannerQuestionStep(
            key: .travelers,
            title: "Who are you traveling with?",
            subtitle: "Group type changes pace and logistics.",
            icon: "person.3.fill",
            options: ["Solo", "Couple", "Family", "Friends group"],
            placeholder: "Example: 2 adults + 1 child",
            skipValue: "Couple"
        ),
        PlannerQuestionStep(
            key: .travelersProfile,
            title: "Age / relationship / flexibility",
            subtitle: "Tell me your constraints to optimize comfort.",
            icon: "figure.2.and.child.holdinghands",
            options: ["Adults only", "With children", "Mixed generations", "Very flexible"],
            placeholder: "Example: parents + teen, no night transfers",
            skipValue: "Very flexible"
        ),
        PlannerQuestionStep(
            key: .budget,
            title: "What is the total budget?",
            subtitle: "I split it into practical categories.",
            icon: "eurosign.bank.building",
            options: ["Smart", "Comfort", "Premium", "Luxury"],
            placeholder: "Example: 2200 EUR total",
            skipValue: "Comfort"
        ),
        PlannerQuestionStep(
            key: .interests,
            title: "Main interests",
            subtitle: "Pick one or combine multiple themes.",
            icon: "star.bubble.fill",
            options: ["Food", "Nature", "Culture", "Adventure"],
            placeholder: "Example: food + design + local markets",
            skipValue: "Culture + Food"
        ),
        PlannerQuestionStep(
            key: .transportation,
            title: "Transportation preferences",
            subtitle: "No live transport API: I optimize based on your preferences.",
            icon: "tram.fill",
            options: ["Metro + walking", "Rental car", "Trains", "Mixed"],
            placeholder: "Example: mostly public transport",
            skipValue: "Mixed"
        ),
        PlannerQuestionStep(
            key: .activities,
            title: "Activity pace",
            subtitle: "Defines daily intensity and backup plans (GetYourGuide style).",
            icon: "ticket.fill",
            options: ["Relaxed", "Balanced", "Full immersion", "Nightlife"],
            placeholder: "Example: balanced days, one long evening",
            skipValue: "Balanced"
        )
    ]
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
