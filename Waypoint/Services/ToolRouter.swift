import Foundation

enum PlannerTool: String, CaseIterable, Hashable {
    case flights
    case restaurants
    case activities
}

enum ToolResult: Hashable {
    case flights(ToolSearchResult<FlightOption>)
    case restaurants(ToolSearchResult<RestaurantOption>)
    case activities(ToolSearchResult<ActivityOption>)
}

protocol ToolRoutering {
    func run(_ tool: PlannerTool, draft: inout TripDraft, destination: DestinationSnapshot?) async -> ToolResult
}

struct DestinationSnapshot: Sendable {
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
}

struct ToolRouter: ToolRoutering {
    typealias FlightsSearch = @Sendable (SearchInput) async -> ToolSearchResult<FlightOption>
    typealias RestaurantsSearch = @Sendable (SearchInput) async -> ToolSearchResult<RestaurantOption>
    typealias ActivitiesSearch = @Sendable (SearchInput) async -> ToolSearchResult<ActivityOption>

    private let flightsSearch: FlightsSearch
    private let restaurantsSearch: RestaurantsSearch
    private let activitiesSearch: ActivitiesSearch

    init(
        flightsSearch: @escaping FlightsSearch = { _ in ToolSearchResult(items: []) },
        restaurantsSearch: @escaping RestaurantsSearch = { _ in ToolSearchResult(items: []) },
        activitiesSearch: @escaping ActivitiesSearch = { _ in ToolSearchResult(items: []) }
    ) {
        self.flightsSearch = flightsSearch
        self.restaurantsSearch = restaurantsSearch
        self.activitiesSearch = activitiesSearch
    }

    func run(_ tool: PlannerTool, draft: inout TripDraft, destination: DestinationSnapshot?) async -> ToolResult {
        let input = SearchInput(
            query: draft.selectedStyles.joined(separator: ", "),
            budget: draft.budget,
            people: draft.people,
            startDate: draft.startDate,
            endDate: draft.endDate,
            destinationName: destination?.name,
            destinationCountry: destination?.country,
            latitude: destination?.latitude,
            longitude: destination?.longitude
        )

        switch tool {
        case .flights:
            let result = await flightsSearch(input)
            if let first = result.items.first {
                addToDraft(
                    activity: DraftActivity(type: .flight, title: "\(first.airline) • €\(Int(first.price))", note: "\(String(format: "%.1f", first.durationHours))h"),
                    draft: &draft
                )
            }
            return .flights(result)

        case .restaurants:
            let result = await restaurantsSearch(input)
            if let first = result.items.first {
                addToDraft(
                    activity: DraftActivity(type: .restaurant, title: first.name, note: "\(first.cuisine) • €\(Int(first.estimatedCost))"),
                    draft: &draft
                )
            }
            return .restaurants(result)

        case .activities:
            let result = await activitiesSearch(input)
            if let first = result.items.first {
                addToDraft(
                    activity: DraftActivity(type: .activity, title: first.title, note: "\(first.category) • €\(Int(first.estimatedCost))"),
                    draft: &draft
                )
            }
            return .activities(result)
        }
    }

    private func addToDraft(activity: DraftActivity, draft: inout TripDraft) {
        if draft.timeline.isEmpty {
            draft.timeline.append(DayPlan(dayIndex: 1, activities: [activity]))
            return
        }
        draft.timeline[0].activities.append(activity)
    }
}
