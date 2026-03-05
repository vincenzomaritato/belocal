import XCTest
@testable import Waypoint

final class CO2EstimatorTests: XCTestCase {
    func testPlaneEstimate() {
        let estimator = CO2Estimator()
        let value = estimator.estimate(distanceKm: 1000, transportType: .plane, people: 2)
        XCTAssertEqual(value, 360, accuracy: 0.001)
    }

    func testTrainEstimate() {
        let estimator = CO2Estimator()
        let value = estimator.estimate(distanceKm: 500, transportType: .train, people: 1)
        XCTAssertEqual(value, 20, accuracy: 0.001)
    }

    func testZeroDistanceReturnsZero() {
        let estimator = CO2Estimator()
        let value = estimator.estimate(distanceKm: 0, transportType: .car, people: 4)
        XCTAssertEqual(value, 0, accuracy: 0.001)
    }
}
