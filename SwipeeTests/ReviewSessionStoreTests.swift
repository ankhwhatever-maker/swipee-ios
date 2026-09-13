import Foundation
import XCTest
@testable import Swipee

@MainActor
final class ReviewSessionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ReviewSessionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testSessionCompletesAfterTenUniquePhotos() {
        let store = ReviewSessionStore(defaults: defaults)

        for index in 0..<ReviewSessionStore.targetCount {
            store.append(
                assetIdentifier: "asset-\(index)",
                sourceConditionKey: "condition-a",
                decision: index.isMultiple(of: 2) ? .trash : .keep
            )
        }

        XCTAssertTrue(store.isComplete)
        XCTAssertEqual(store.items.count, 10)
        XCTAssertEqual(store.deletionCount, 5)
    }

    func testSessionItemsPersistAndCanBeUpdated() {
        let firstStore = ReviewSessionStore(defaults: defaults)
        firstStore.append(
            assetIdentifier: "asset-1",
            sourceConditionKey: "condition-a",
            decision: .keep
        )
        firstStore.updateDecision(assetIdentifier: "asset-1", decision: .trash)

        let restoredStore = ReviewSessionStore(defaults: defaults)

        XCTAssertEqual(restoredStore.items.first?.decision, .trash)
        XCTAssertEqual(restoredStore.items.first?.sourceConditionKey, "condition-a")
    }

    func testRemoveLastAllowsEverySessionActionToBeUndoneInReverseOrder() {
        let store = ReviewSessionStore(defaults: defaults)
        store.append(assetIdentifier: "asset-1", sourceConditionKey: "condition-a", decision: .trash)
        store.append(assetIdentifier: "asset-2", sourceConditionKey: "condition-a", decision: .keep)
        store.append(assetIdentifier: "asset-3", sourceConditionKey: "condition-a", decision: .keep)

        XCTAssertEqual(store.removeLast()?.assetIdentifier, "asset-3")
        XCTAssertEqual(store.removeLast()?.assetIdentifier, "asset-2")
        XCTAssertEqual(store.removeLast()?.assetIdentifier, "asset-1")
        XCTAssertNil(store.removeLast())
        XCTAssertTrue(ReviewSessionStore(defaults: defaults).items.isEmpty)
    }

    func testDeletionSelectionCanBeRestoredAsKeep() {
        let store = ReviewSessionStore(defaults: defaults)
        store.append(
            assetIdentifier: "asset-1",
            sourceConditionKey: "condition-a",
            decision: .keep
        )

        store.updateDecision(assetIdentifier: "asset-1", decision: .trash)
        store.updateDecision(assetIdentifier: "asset-1", decision: .keep)

        XCTAssertEqual(store.items.first?.decision, .keep)
    }

    func testFinishingSessionPersistsCumulativeDeletedCount() {
        let firstStore = ReviewSessionStore(defaults: defaults)
        firstStore.append(
            assetIdentifier: "asset-1",
            sourceConditionKey: "condition-a",
            decision: .trash
        )
        firstStore.finish(deletedCount: 1)

        let secondStore = ReviewSessionStore(defaults: defaults)
        secondStore.finish(deletedCount: 3)

        XCTAssertTrue(secondStore.items.isEmpty)
        XCTAssertEqual(secondStore.totalDeletedCount, 4)
        XCTAssertEqual(ReviewSessionStore(defaults: defaults).totalDeletedCount, 4)
    }

    func testPendingDeletionMigrationDoesNotDuplicateSessionItems() {
        let store = ReviewSessionStore(defaults: defaults)
        let record = PendingDeletionRecord(
            assetIdentifier: "asset-1",
            sourceConditionKey: "condition-a"
        )

        store.importPendingRecords([record, record])

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.decision, .trash)
    }
}
