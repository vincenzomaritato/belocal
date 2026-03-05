import Foundation

struct LocalFeedbackAggregator {
    func summary(for destination: Destination, localInsight: LocalInsight?, feedback: [TravelerFeedback]) -> String {
        let travelerFeedback = feedback.filter { $0.sourceType == .traveler }
        let localFeedback = feedback.filter { $0.sourceType == .local }

        let travelerSentiment: String = {
            guard !travelerFeedback.isEmpty else { return "Traveler feedback is still limited." }
            let averageRating = Double(travelerFeedback.map(\.rating).reduce(0, +)) / Double(travelerFeedback.count)
            if averageRating >= 4.2 { return "Travelers report a very positive experience." }
            if averageRating >= 3.3 { return "Travelers report mostly positive experiences with some caveats." }
            return "Travelers reported mixed outcomes and some friction points."
        }()

        let localSentiment: String = {
            guard !localFeedback.isEmpty else { return "Local voices are not available yet." }
            let averageRating = Double(localFeedback.map(\.rating).reduce(0, +)) / Double(localFeedback.count)
            if averageRating >= 4.2 { return "Locals strongly endorse this destination." }
            if averageRating >= 3.3 { return "Locals report generally solid day-to-day quality." }
            return "Locals highlight trade-offs to consider." 
        }()

        let localLine = localInsight?.summaryText ?? "Local community data is currently unavailable."
        return "\(travelerSentiment) \(localSentiment) \(localLine)"
    }
}
