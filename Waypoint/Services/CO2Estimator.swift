import Foundation

struct CO2Estimator {
    let emissionFactorsKgPerKmPerPerson: [TransportType: Double] = [
        .plane: 0.18,
        .train: 0.04,
        .car: 0.12
    ]

    func estimate(distanceKm: Double, transportType: TransportType, people: Int) -> Double {
        let factor = emissionFactorsKgPerKmPerPerson[transportType] ?? 0.18
        return max(0, distanceKm) * factor * Double(max(1, people))
    }
}
