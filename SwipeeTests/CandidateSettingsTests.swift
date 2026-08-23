import Photos
import XCTest
@testable import Swipee

final class CandidateSettingsTests: XCTestCase {
    func testDefaultConditionMatchesProductRequirement() {
        let settings = CandidateSettings()
        XCTAssertEqual(settings.period, .all)
        XCTAssertEqual(settings.mediaKinds, [.photo, .screenshot])
        XCTAssertFalse(settings.mediaKinds.contains(.video))
    }

    func testConditionKeyIsIndependentOfSetOrder() {
        let first = CandidateSettings(period: .threeMonths, mediaKinds: [.photo, .screenshot])
        let second = CandidateSettings(period: .threeMonths, mediaKinds: [.screenshot, .photo])
        XCTAssertEqual(first.conditionKey, second.conditionKey)
    }

    func testThreeYearBoundaryIsGenerated() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = CandidatePeriod.threeYears.startDate(now: now, calendar: Calendar(identifier: .gregorian))
        XCTAssertNotNil(start)
        XCTAssertLessThan(start!, now)
    }
}
