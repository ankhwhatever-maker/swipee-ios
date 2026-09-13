import Foundation
import XCTest
@testable import Swipee

@MainActor
final class DuplicateSessionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "DuplicateSessionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testGroupsKeepIndependentPersistedSessions() {
        let store = DuplicateSessionStore(defaults: defaults)
        store.append(groupIdentifier: "group-a", assetIdentifier: "asset-1", decision: .trash)
        store.append(groupIdentifier: "group-b", assetIdentifier: "asset-2", decision: .keep)

        let restored = DuplicateSessionStore(defaults: defaults)

        XCTAssertEqual(restored.items(for: "group-a").map(\.assetIdentifier), ["asset-1"])
        XCTAssertEqual(restored.items(for: "group-b").map(\.assetIdentifier), ["asset-2"])
        XCTAssertEqual(restored.items(for: "group-a").first?.sourceConditionKey, "duplicates|group-a")
    }

    func testEveryActionCanBeUndoneInReverseOrder() {
        let store = DuplicateSessionStore(defaults: defaults)
        store.append(groupIdentifier: "group", assetIdentifier: "asset-1", decision: .trash)
        store.append(groupIdentifier: "group", assetIdentifier: "asset-2", decision: .keep)
        store.append(groupIdentifier: "group", assetIdentifier: "asset-3", decision: .keep)

        XCTAssertEqual(store.removeLast(groupIdentifier: "group")?.assetIdentifier, "asset-3")
        XCTAssertEqual(store.removeLast(groupIdentifier: "group")?.assetIdentifier, "asset-2")
        XCTAssertEqual(store.removeLast(groupIdentifier: "group")?.assetIdentifier, "asset-1")
        XCTAssertNil(store.removeLast(groupIdentifier: "group"))
    }

    func testReviewSelectionCanBeRestoredAsKeep() {
        let store = DuplicateSessionStore(defaults: defaults)
        store.append(groupIdentifier: "group", assetIdentifier: "asset-1", decision: .keep)

        store.updateDecision(
            groupIdentifier: "group",
            assetIdentifier: "asset-1",
            decision: .trash
        )
        store.updateDecision(
            groupIdentifier: "group",
            assetIdentifier: "asset-1",
            decision: .keep
        )

        XCTAssertEqual(store.items(for: "group").first?.decision, .keep)
    }

    func testInitiallyDeletedItemRestoresAsKeepInReview() {
        let store = DuplicateSessionStore(defaults: defaults)
        store.append(groupIdentifier: "group", assetIdentifier: "asset-1", decision: .trash)

        guard let item = store.items(for: "group").first else {
            return XCTFail("Expected a review item")
        }
        store.updateDecision(
            groupIdentifier: "group",
            assetIdentifier: item.assetIdentifier,
            decision: .keep
        )

        XCTAssertEqual(store.items(for: "group").first?.decision, .keep)
    }

    func testClearingOneGroupDoesNotClearAnother() {
        let store = DuplicateSessionStore(defaults: defaults)
        store.append(groupIdentifier: "group-a", assetIdentifier: "asset-1", decision: .keep)
        store.append(groupIdentifier: "group-b", assetIdentifier: "asset-2", decision: .keep)

        store.clear(groupIdentifier: "group-a")

        XCTAssertTrue(store.items(for: "group-a").isEmpty)
        XCTAssertEqual(DuplicateSessionStore(defaults: defaults).items(for: "group-b").count, 1)
    }
}

@MainActor
final class DuplicateReviewedStoreTests: XCTestCase {
    func testReviewedGroupsPersistAndCanBeShownAgain() {
        let suiteName = "DuplicateReviewedStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        DuplicateReviewedStore(defaults: defaults).markReviewed("group-a")
        let restored = DuplicateReviewedStore(defaults: defaults)
        XCTAssertTrue(restored.contains("group-a"))

        restored.clear()
        XCTAssertFalse(DuplicateReviewedStore(defaults: defaults).contains("group-a"))
    }
}

final class DuplicatePhotoGroupTests: XCTestCase {
    func testIdentifierDoesNotDependOnAssetOrder() {
        XCTAssertEqual(
            DuplicatePhotoGroup(assetIdentifiers: ["b", "a"]).id,
            DuplicatePhotoGroup(assetIdentifiers: ["a", "b"]).id
        )
    }
}
