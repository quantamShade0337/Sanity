import XCTest
@testable import Sanity

final class SanityTests: XCTestCase {
    func testApplicationIdentity() {
        XCTAssertEqual(AppInfo.name, "Sanity")
    }

    func testBoostRaisesLoudnessWithoutExceedingOutputRange() {
        let source = (0..<48_000).map { frame in
            Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000))
        }
        let boosted = source.map { BoostSoftClipper.sample($0, gain: 2) }
        let sourceRMS = sqrt(source.reduce(0) { $0 + $1 * $1 } / Float(source.count))
        let boostedRMS = sqrt(boosted.reduce(0) { $0 + $1 * $1 } / Float(boosted.count))

        XCTAssertGreaterThan(boostedRMS, sourceRMS)
        XCTAssertTrue(boosted.allSatisfy { abs($0) <= 1 })
    }

    func testBoostCurveIsContinuousFromUnity() {
        let sample: Float = 0.42
        XCTAssertEqual(BoostSoftClipper.sample(sample, gain: 1), sample)
        XCTAssertEqual(BoostSoftClipper.sample(sample, gain: 0.5), sample * 0.5)
        XCTAssertGreaterThan(BoostSoftClipper.sample(sample, gain: 1.01), sample)
    }

}
