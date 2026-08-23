import Foundation
import Photos
import XCTest
@testable import Swipee

@MainActor
final class PendingDeletionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PendingDeletionStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEnqueueCreatesPendingDeletionRecord() {
        let store = PendingDeletionStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        store.enqueue(assetIdentifier: "asset-1", sourceConditionKey: "condition-a", queuedAt: date)

        XCTAssertEqual(
            store.records,
            [PendingDeletionRecord(assetIdentifier: "asset-1", sourceConditionKey: "condition-a", queuedAt: date)]
        )
        XCTAssertEqual(store.records.first?.state, .pendingDeletion)
    }

    func testPendingAssetIsExcludedGloballyRegardlessOfCondition() {
        let store = PendingDeletionStore(defaults: defaults)
        store.enqueue(assetIdentifier: "asset-1", sourceConditionKey: "condition-a")

        XCTAssertTrue(store.contains(assetIdentifier: "asset-1"))
        XCTAssertEqual(store.assetIdentifiers, ["asset-1"])
    }

    func testEnqueueDoesNotDuplicateAnAssetAcrossConditions() {
        let store = PendingDeletionStore(defaults: defaults)
        store.enqueue(assetIdentifier: "asset-1", sourceConditionKey: "condition-a")
        store.enqueue(assetIdentifier: "asset-1", sourceConditionKey: "condition-b")

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.sourceConditionKey, "condition-a")
    }

    func testRecordsPersistAcrossStoreInstances() {
        let firstStore = PendingDeletionStore(defaults: defaults)
        firstStore.enqueue(assetIdentifier: "asset-1", sourceConditionKey: "condition-a")

        let restoredStore = PendingDeletionStore(defaults: defaults)

        XCTAssertTrue(restoredStore.contains(assetIdentifier: "asset-1"))
        XCTAssertEqual(restoredStore.records.first?.sourceConditionKey, "condition-a")
    }

    func testRemoveReturnsSourceRecordAndClearsPendingState() {
        let store = PendingDeletionStore(defaults: defaults)
        store.enqueue(assetIdentifier: "asset-1", sourceConditionKey: "condition-a")

        let removed = store.remove(assetIdentifier: "asset-1")

        XCTAssertEqual(removed?.sourceConditionKey, "condition-a")
        XCTAssertFalse(store.contains(assetIdentifier: "asset-1"))
    }

    func testRemoveAllClearsPersistedRecords() {
        let store = PendingDeletionStore(defaults: defaults)
        store.enqueue(assetIdentifier: "asset-1", sourceConditionKey: "condition-a")
        store.enqueue(assetIdentifier: "asset-2", sourceConditionKey: "condition-b")

        store.removeAll()

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(PendingDeletionStore(defaults: defaults).records.isEmpty)
    }

    func testRemoveSetClearsOnlySuccessfullyHandledAssets() {
        let store = PendingDeletionStore(defaults: defaults)
        store.enqueue(assetIdentifier: "asset-1", sourceConditionKey: "condition-a")
        store.enqueue(assetIdentifier: "asset-2", sourceConditionKey: "condition-b")
        store.enqueue(assetIdentifier: "asset-3", sourceConditionKey: "condition-c")

        store.remove(assetIdentifiers: ["asset-1", "asset-3"])

        XCTAssertEqual(store.assetIdentifiers, ["asset-2"])
        XCTAssertEqual(PendingDeletionStore(defaults: defaults).assetIdentifiers, ["asset-2"])
    }

    func testReconcileRemovesAssetsDeletedOutsideSwipee() {
        let store = PendingDeletionStore(defaults: defaults)
        store.enqueue(assetIdentifier: "available", sourceConditionKey: "condition-a")
        store.enqueue(assetIdentifier: "deleted-externally", sourceConditionKey: "condition-b")

        let removed = store.reconcile(validAssetIdentifiers: ["available"])

        XCTAssertEqual(removed.map(\.assetIdentifier), ["deleted-externally"])
        XCTAssertEqual(store.assetIdentifiers, ["available"])
    }

    func testPhotoLibraryUserCancellationIsNotTreatedAsFailure() {
        let cancellation = NSError(domain: PHPhotosErrorDomain, code: 3072)
        let otherError = NSError(domain: PHPhotosErrorDomain, code: -1)

        XCTAssertTrue(PhotoLibraryService.isUserCancellation(cancellation))
        XCTAssertFalse(PhotoLibraryService.isUserCancellation(otherError))
    }
}
