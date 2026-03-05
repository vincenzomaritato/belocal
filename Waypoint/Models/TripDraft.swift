import Foundation

struct TripDraft: Codable {
    var destinationId: UUID?
    var budget: Double
    var startDate: Date
    var endDate: Date
    var people: Int
    var selectedStyles: [String]
    var timeline: [DayPlan]
    var notes: String

    init(
        destinationId: UUID? = nil,
        budget: Double = 2200,
        startDate: Date = .now,
        endDate: Date = Calendar.current.date(byAdding: .day, value: 4, to: .now) ?? .now,
        people: Int = 2,
        selectedStyles: [String] = ["Culture"],
        timeline: [DayPlan] = [DayPlan(dayIndex: 1), DayPlan(dayIndex: 2), DayPlan(dayIndex: 3)],
        notes: String = ""
    ) {
        self.destinationId = destinationId
        self.budget = budget
        self.startDate = startDate
        self.endDate = endDate
        self.people = people
        self.selectedStyles = selectedStyles
        self.timeline = timeline
        self.notes = notes
    }
}

struct DayPlan: Identifiable, Codable, Hashable {
    var id: UUID
    var dayIndex: Int
    var title: String
    var activities: [DraftActivity]

    init(id: UUID = UUID(), dayIndex: Int, title: String? = nil, activities: [DraftActivity] = []) {
        self.id = id
        self.dayIndex = dayIndex
        self.title = title ?? "Day \(dayIndex)"
        self.activities = activities
    }
}

struct DraftActivity: Identifiable, Codable, Hashable {
    var id: UUID
    var type: ActivityType
    var title: String
    var note: String

    init(id: UUID = UUID(), type: ActivityType, title: String, note: String = "") {
        self.id = id
        self.type = type
        self.title = title
        self.note = note
    }
}
