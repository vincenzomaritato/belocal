import Foundation
import Observation
import SwiftData
import SwiftUI

struct AgentMessage: Identifiable, Hashable {
    let id: UUID
    let title: String
    let body: String
    let isUser: Bool
    let suggestions: [String]

    init(id: UUID = UUID(), title: String, body: String, isUser: Bool = false, suggestions: [String] = []) {
        self.id = id
        self.title = title
        self.body = body
        self.isUser = isUser
        self.suggestions = suggestions
    }
}

private enum PlannerCommand {
    case help
    case runTool(PlannerTool)
    case addDay
    case removeDay(Int)
    case setBudget(Double)
    case setPeople(Int)
    case addStyle(String)
    case setDestination(String)
    case save
    case unknown(String)
}

@MainActor
@Observable
final class PlannerViewModel {
    var draft = TripDraft()
    var userMessage = ""
    var agentMessages: [AgentMessage] = [
        AgentMessage(
            title: L10n.tr("Travel Agent"),
            body: L10n.tr("Use natural language or commands. Try `/help` to see orchestration commands."),
            suggestions: ["/restaurants", "/activities", "/addday"]
        )
    ]

    var isToolLoading: Set<PlannerTool> = []
    var latestFlights: [FlightOption] = []
    var latestRestaurants: [RestaurantOption] = []
    var latestActivities: [ActivityOption] = []

    let commandHints: [String] = [
        "/help",
        "/restaurants",
        "/activities",
        "/addday",
        "/save"
    ]

    func applySuggestion(_ suggestion: String) {
        if !draft.selectedStyles.contains(suggestion) {
            withAnimation(.easeInOut(duration: 0.2)) {
                draft.selectedStyles.append(suggestion)
            }
            appendAgent(L10n.f("Added style `%@`. I can now run `/activities` or `/restaurants`.", suggestion), suggestions: ["/activities", "/restaurants", "/save"])
        }
    }

    func sendMessage(
        toolRouter: ToolRouter,
        context: ModelContext,
        homeViewModel: HomeViewModel,
        bootstrap: AppBootstrap
    ) {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userMessage = ""

        handleInput(
            trimmed,
            emitUserMessage: true,
            toolRouter: toolRouter,
            context: context,
            homeViewModel: homeViewModel,
            bootstrap: bootstrap
        )
    }

    func performQuickAction(
        _ action: String,
        toolRouter: ToolRouter,
        context: ModelContext,
        homeViewModel: HomeViewModel,
        bootstrap: AppBootstrap
    ) {
        let mapped: String
        switch action {
        case L10n.tr("Find restaurants"): mapped = "/restaurants"
        case L10n.tr("Find activities"): mapped = "/activities"
        case L10n.tr("Add a day"): mapped = "/addday"
        case L10n.tr("Save Trip Draft"): mapped = "/save"
        default: mapped = action
        }

        handleInput(
            mapped,
            emitUserMessage: false,
            toolRouter: toolRouter,
            context: context,
            homeViewModel: homeViewModel,
            bootstrap: bootstrap
        )
    }

    private func handleInput(
        _ input: String,
        emitUserMessage: Bool,
        toolRouter: ToolRouter,
        context: ModelContext,
        homeViewModel: HomeViewModel,
        bootstrap: AppBootstrap
    ) {
        if emitUserMessage {
            agentMessages.append(AgentMessage(title: L10n.tr("You"), body: input, isUser: true))
        }

        if input.hasPrefix("/") {
            let command = parseCommand(input)
            runCommand(command, toolRouter: toolRouter, context: context, homeViewModel: homeViewModel, bootstrap: bootstrap)
        } else {
            runNaturalLanguage(input, toolRouter: toolRouter, context: context, homeViewModel: homeViewModel, bootstrap: bootstrap)
        }
    }

    private func parseCommand(_ input: String) -> PlannerCommand {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = normalized.split(separator: " ").map(String.init)
        guard let head = parts.first?.lowercased() else { return .help }

        switch head {
        case "/help": return .help
        case "/flights": return .runTool(.flights)
        case "/restaurants": return .runTool(.restaurants)
        case "/activities": return .runTool(.activities)
        case "/addday": return .addDay
        case "/removeday":
            guard parts.count > 1, let value = Int(parts[1]) else { return .unknown(L10n.tr("Use `/removeday 2`")) }
            return .removeDay(value)
        case "/budget":
            guard parts.count > 1 else { return .unknown(L10n.tr("Use `/budget 2400`")) }
            let raw = parts[1].replacingOccurrences(of: ",", with: ".")
            guard let budget = Double(raw) else { return .unknown(L10n.tr("Budget must be numeric, e.g. `/budget 2400`")) }
            return .setBudget(budget)
        case "/people":
            guard parts.count > 1, let people = Int(parts[1]) else { return .unknown(L10n.tr("Use `/people 2`")) }
            return .setPeople(people)
        case "/style":
            guard parts.count > 1 else { return .unknown(L10n.tr("Use `/style Culture`")) }
            return .addStyle(parts.dropFirst().joined(separator: " "))
        case "/destination":
            guard parts.count > 1 else { return .unknown(L10n.tr("Use `/destination Lisbon`")) }
            return .setDestination(parts.dropFirst().joined(separator: " "))
        case "/save":
            return .save
        default:
            return .unknown(L10n.f("Unknown command: `%@`", head))
        }
    }

    private func runCommand(
        _ command: PlannerCommand,
        toolRouter: ToolRouter,
        context: ModelContext,
        homeViewModel: HomeViewModel,
        bootstrap: AppBootstrap
    ) {
        switch command {
        case .help:
            appendAgent(
                L10n.tr("Available commands: `/restaurants`, `/activities`, `/addday`, `/removeday n`, `/budget n`, `/people n`, `/style name`, `/destination name`, `/save`. Flight search is disabled in this build."),
                suggestions: ["/activities", "/restaurants", "/save"]
            )

        case .runTool(let tool):
            runTool(tool, router: toolRouter, destination: selectedDestinationSnapshot(in: homeViewModel))

        case .addDay:
            addDay()
            appendAgent(L10n.tr("Added one day to your timeline."), suggestions: ["/activities", "/save"])

        case .removeDay(let dayIndex):
            guard let day = draft.timeline.first(where: { $0.dayIndex == dayIndex }) else {
                appendAgent(L10n.f("Day %1$lld not found. Current days: %2$@.", dayIndex, draft.timeline.map(\.dayIndex).map(String.init).joined(separator: ", ")))
                return
            }
            removeDay(day)
            appendAgent(L10n.f("Removed Day %lld.", dayIndex))

        case .setBudget(let budget):
            draft.budget = min(max(budget, 400), 7000)
            appendAgent(L10n.f("Budget updated to €%lld.", Int(draft.budget)), suggestions: ["/activities", "/restaurants"])

        case .setPeople(let people):
            draft.people = min(max(people, 1), 8)
            appendAgent(L10n.f("Traveler count updated to %lld.", draft.people), suggestions: ["/activities", "/save"])

        case .addStyle(let style):
            let normalizedStyle = style.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedStyle.isEmpty else {
                appendAgent(L10n.tr("Style cannot be empty."))
                return
            }
            if !draft.selectedStyles.contains(normalizedStyle) {
                draft.selectedStyles.append(normalizedStyle)
            }
            appendAgent(L10n.f("Style `%@` added.", normalizedStyle), suggestions: ["/activities", "/restaurants"])

        case .setDestination(let value):
            let query = value.lowercased()
            let match = homeViewModel.destinations.first { destination in
                destination.name.lowercased().contains(query) || destination.country.lowercased().contains(query)
            }
            guard let match else {
                appendAgent(L10n.f("No destination matched `%@`. Try `/destination Lisbon`.", value))
                return
            }
            draft.destinationId = match.id
            appendAgent(L10n.f("Destination set to %@, %@.", match.name, match.country), suggestions: ["/activities", "/restaurants", "/save"])

        case .save:
            saveDraftAsTrip(context: context, homeViewModel: homeViewModel, bootstrap: bootstrap)

        case .unknown(let reason):
            appendAgent(reason, suggestions: ["/help"])
        }
    }

    private func runNaturalLanguage(
        _ input: String,
        toolRouter: ToolRouter,
        context: ModelContext,
        homeViewModel: HomeViewModel,
        bootstrap: AppBootstrap
    ) {
        let lower = input.lowercased()

        if lower.contains("flight") || lower.contains("volo") {
            runTool(.flights, router: toolRouter, destination: selectedDestinationSnapshot(in: homeViewModel))
            return
        }

        if lower.contains("restaurant") || lower.contains("food") || lower.contains("ristor") {
            runTool(.restaurants, router: toolRouter, destination: selectedDestinationSnapshot(in: homeViewModel))
            return
        }

        if lower.contains("activity") || lower.contains("activities") || lower.contains("things to do") {
            runTool(.activities, router: toolRouter, destination: selectedDestinationSnapshot(in: homeViewModel))
            return
        }

        if lower.contains("add day") {
            addDay()
            appendAgent(L10n.tr("Added a new day. Ask me for activities when ready."), suggestions: ["/activities", "/save"])
            return
        }

        if lower.contains("save") {
            saveDraftAsTrip(context: context, homeViewModel: homeViewModel, bootstrap: bootstrap)
            return
        }

        let styleCandidates = ["beach", "culture", "food", "nature", "adventure", "wellness"]
        if let style = styleCandidates.first(where: { lower.contains($0) }) {
            applySuggestion(style.capitalized)
            return
        }

        appendAgent(
            L10n.tr("I can orchestrate tools with commands. Use `/help` or ask like “find restaurants and add one activity”."),
            suggestions: ["/help", "/restaurants", "/activities"]
        )
    }

    func runTool(_ tool: PlannerTool, router: ToolRouter, destination: DestinationSnapshot?) {
        guard !isToolLoading.contains(tool) else { return }
        isToolLoading.insert(tool)

        Task {
            var mutableDraft = draft
            let result = await router.run(tool, draft: &mutableDraft, destination: destination)

            await MainActor.run {
                draft = mutableDraft
                isToolLoading.remove(tool)

                switch result {
                case .flights(let result):
                    latestFlights = result.items
                    appendToolMessage(
                        result: result,
                        successMessage: L10n.f("Flight options are ready. Added %@ to Day 1.", result.items.first?.airline ?? L10n.tr("the top option")),
                        emptyMessage: L10n.tr("No flight options found for this plan right now."),
                        suggestions: ["/activities", "/save"]
                    )
                case .restaurants(let result):
                    latestRestaurants = result.items
                    appendToolMessage(
                        result: result,
                        successMessage: L10n.tr("Restaurant options are ready. Added one local spot to Day 1."),
                        emptyMessage: L10n.tr("No restaurant matches found for this plan yet."),
                        suggestions: ["/activities", "/save"]
                    )
                case .activities(let result):
                    latestActivities = result.items
                    appendToolMessage(
                        result: result,
                        successMessage: L10n.tr("Activity options are ready. Added one activity to your timeline."),
                        emptyMessage: L10n.tr("No activities matched this plan yet."),
                        suggestions: ["/addday", "/save"]
                    )
                }
            }
        }
    }

    private func appendToolMessage<Item: Sendable>(
        result: ToolSearchResult<Item>,
        successMessage: String,
        emptyMessage: String,
        suggestions: [String]
    ) {
        if let message = result.message, !message.isEmpty {
            appendAgent(message, suggestions: suggestions)
            return
        }

        if result.items.isEmpty {
            appendAgent(emptyMessage, suggestions: suggestions)
            return
        }

        appendAgent(successMessage, suggestions: suggestions)
    }

    private func selectedDestinationSnapshot(in homeViewModel: HomeViewModel) -> DestinationSnapshot? {
        guard let destination = selectedDestination(in: homeViewModel) else { return nil }
        return DestinationSnapshot(
            name: destination.name,
            country: destination.country,
            latitude: destination.latitude,
            longitude: destination.longitude
        )
    }

    func addDay() {
        let next = (draft.timeline.map(\.dayIndex).max() ?? 0) + 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            draft.timeline.append(DayPlan(dayIndex: next))
        }
    }

    func removeDay(_ day: DayPlan) {
        guard draft.timeline.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            draft.timeline.removeAll(where: { $0.id == day.id })
            normalizeDays()
        }
    }

    func moveDays(from source: IndexSet, to destination: Int) {
        draft.timeline.move(fromOffsets: source, toOffset: destination)
        normalizeDays()
    }

    private func normalizeDays() {
        for index in draft.timeline.indices {
            draft.timeline[index].dayIndex = index + 1
            draft.timeline[index].title = L10n.f("Day %lld", index + 1)
        }
    }

    func saveDraftAsTrip(context: ModelContext, homeViewModel: HomeViewModel, bootstrap: AppBootstrap) {
        guard
            let profile = homeViewModel.userProfile,
            let destinationId = draft.destinationId ?? homeViewModel.recommendations.first?.destination.id,
            let destination = homeViewModel.destinations.first(where: { $0.id == destinationId })
        else {
            appendAgent(L10n.tr("Pick a destination before saving."), suggestions: ["/destination Lisbon"])
            return
        }

        let distanceKm = TravelDistanceCalculator.distanceKm(
            from: TravelDistanceCalculator.homeCoordinate(from: profile),
            to: (destination.latitude, destination.longitude)
        )
        destination.distanceKm = distanceKm

        let co2 = bootstrap.co2Estimator.estimate(
            distanceKm: distanceKm,
            transportType: .plane,
            people: draft.people
        )

        let trip = Trip(
            userId: profile.id,
            destinationId: destination.id,
            startDate: draft.startDate,
            endDate: draft.endDate,
            transportType: .plane,
            people: draft.people,
            budgetSpent: min(draft.budget, profile.budgetMax),
            co2Estimated: co2,
            ecoScoreSnapshot: destination.ecoScore
        )
        context.insert(trip)

        var persistedActivities: [ActivityItem] = []
        for day in draft.timeline {
            for activity in day.activities {
                let item = ActivityItem(
                    tripId: trip.id,
                    type: activity.type,
                    title: activity.title,
                    note: "\(day.title): \(activity.note)"
                )
                context.insert(item)
                persistedActivities.append(item)
            }
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
            homeViewModel.load(context: context, bootstrap: bootstrap)
            appendAgent(L10n.tr("Trip saved. It is now available in Your Trips."))
        } catch {
            appendAgent(L10n.tr("Save failed. I could not persist this draft locally."))
        }
    }

    private func appendAgent(_ text: String, suggestions: [String] = []) {
        agentMessages.append(AgentMessage(title: L10n.tr("Agent"), body: text, isUser: false, suggestions: suggestions))
    }

    private func selectedDestination(in homeViewModel: HomeViewModel) -> Destination? {
        if let id = draft.destinationId {
            return homeViewModel.destinations.first(where: { $0.id == id })
        }
        return homeViewModel.recommendations.first?.destination
    }
}
