import Photos
import XCTest
@testable import Swipee

final class CandidateSettingsTests: XCTestCase {
    func testDefaultConditionMatchesProductRequirement() {
        let settings = CandidateSettings()
        XCTAssertEqual(settings.period, .all)
        XCTAssertEqual(settings.mediaKinds, [.photo, .screenshot])
        XCTAssertFalse(settings.mediaKinds.contains(.video))
        XCTAssertTrue(settings.includesFavorites)
        XCTAssertEqual(settings.dateMode, .recent)
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

    func testFavoriteFilterChangesConditionKeyOnlyWhenFavoritesAreExcluded() {
        let included = CandidateSettings(includesFavorites: true)
        let excluded = CandidateSettings(includesFavorites: false)

        XCTAssertEqual(included.conditionKey, "v1|unreviewed|4|photo,screenshot")
        XCTAssertNotEqual(included.conditionKey, excluded.conditionKey)
    }

    func testOlderSavedSettingsDefaultToIncludingFavorites() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "period": CandidatePeriod.threeMonths.rawValue,
            "mediaKinds": [CandidateMediaKind.photo.rawValue]
        ])

        let decoded = try JSONDecoder().decode(CandidateSettings.self, from: data)

        XCTAssertEqual(decoded.period, .threeMonths)
        XCTAssertEqual(decoded.mediaKinds, [.photo])
        XCTAssertTrue(decoded.includesFavorites)
        XCTAssertEqual(decoded.dateMode, .recent)
    }

    func testCustomDateBoundsIncludeTheEntireEndDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 4, day: 1)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 8, day: 31)))
        let expectedEnd = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 9, day: 1)))
        let settings = CandidateSettings(
            dateMode: .custom,
            customStartDate: start,
            customEndDate: end
        )

        let bounds = settings.dateBounds(calendar: calendar)

        XCTAssertEqual(bounds.start, start)
        XCTAssertEqual(bounds.endExclusive, expectedEnd)
    }

    func testCustomDatesArePartOfConditionKey() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 4, day: 1)))
        let secondStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 4, day: 2)))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 8, day: 31)))

        let first = CandidateSettings(dateMode: .custom, customStartDate: firstStart, customEndDate: end)
        let second = CandidateSettings(dateMode: .custom, customStartDate: secondStart, customEndDate: end)

        XCTAssertNotEqual(first.conditionKey, second.conditionKey)
    }
}
