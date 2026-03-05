import Foundation

enum PlannerTool: String, CaseIterable, Hashable {
    case flights
    case restaurants
    case activities
}

enum ToolResult: Hashable {
    case flights([FlightOption])
    case restaurants([RestaurantOption])
    case activities([ActivityOption])
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
    typealias FlightsSearch = @Sendable (SearchInput) async -> [FlightOption]
    typealias RestaurantsSearch = @Sendable (SearchInput) async -> [RestaurantOption]
    typealias ActivitiesSearch = @Sendable (SearchInput) async -> [ActivityOption]

    private let flightsSearch: FlightsSearch
    private let restaurantsSearch: RestaurantsSearch
    private let activitiesSearch: ActivitiesSearch

    init(
        flightsSearch: @escaping FlightsSearch = { _ in [] },
        restaurantsSearch: @escaping RestaurantsSearch = { _ in [] },
        activitiesSearch: @escaping ActivitiesSearch = { _ in [] }
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
            let options = await flightsSearch(input)
            if let first = options.first {
                addToDraft(
                    activity: DraftActivity(type: .flight, title: "\(first.airline) • €\(Int(first.price))", note: "\(String(format: "%.1f", first.durationHours))h"),
                    draft: &draft
                )
            }
            return .flights(options)

        case .restaurants:
            let options = await restaurantsSearch(input)
            if let first = options.first {
                addToDraft(
                    activity: DraftActivity(type: .restaurant, title: first.name, note: "\(first.cuisine) • €\(Int(first.estimatedCost))"),
                    draft: &draft
                )
            }
            return .restaurants(options)

        case .activities:
            let options = await activitiesSearch(input)
            if let first = options.first {
                addToDraft(
                    activity: DraftActivity(type: .activity, title: first.title, note: "\(first.category) • €\(Int(first.estimatedCost))"),
                    draft: &draft
                )
            }
            return .activities(options)
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
