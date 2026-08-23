import Foundation
import XCTest
@testable import Swipee

@MainActor
final class ReviewHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ReviewHistoryStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testRemoveMakesKeptAssetUnreviewedForTheSameCondition() {
        let store = ReviewHistoryStore(defaults: defaults)
        store.record(assetIdentifier: "asset-1", conditionKey: "condition-a", decision: .keep)

        let removed = store.remove(assetIdentifier: "asset-1", conditionKey: "condition-a")

        XCTAssertEqual(removed?.decision, .keep)
        XCTAssertFalse(store.hasReviewed(assetIdentifier: "asset-1", conditionKey: "condition-a"))
        XCTAssertTrue(ReviewHistoryStore(defaults: defaults).records.isEmpty)
    }

    func testRemoveDoesNotAffectAnotherCondition() {
        let store = ReviewHistoryStore(defaults: defaults)
        store.record(assetIdentifier: "asset-1", conditionKey: "condition-a", decision: .keep)
        store.record(assetIdentifier: "asset-1", conditionKey: "condition-b", decision: .favorite)

        store.remove(assetIdentifier: "asset-1", conditionKey: "condition-a")

        XCTAssertFalse(store.hasReviewed(assetIdentifier: "asset-1", conditionKey: "condition-a"))
        XCTAssertTrue(store.hasReviewed(assetIdentifier: "asset-1", conditionKey: "condition-b"))
    }
}
