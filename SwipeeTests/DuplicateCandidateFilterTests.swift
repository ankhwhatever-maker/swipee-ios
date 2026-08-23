import XCTest
@testable import Swipee

final class DuplicateCandidateFilterTests: XCTestCase {
    func testSameBurstIsCandidateEvenWithoutCreationDates() {
        let metadata = [
            item("a", timestamp: nil, burst: "burst-1"),
            item("b", timestamp: nil, burst: "burst-1")
        ]

        XCTAssertEqual(
            DuplicateCandidateFilter.candidateIdentifiers(from: metadata, excluding: []),
            ["a", "b"]
        )
    }

    func testSameSizeWithinTenSecondsIsCandidate() {
        let metadata = [
            item("a", timestamp: 100),
            item("b", timestamp: 110)
        ]

        XCTAssertEqual(
            DuplicateCandidateFilter.candidateIdentifiers(from: metadata, excluding: []),
            ["a", "b"]
        )
    }

    func testUnrelatedPhotosAreNotCandidates() {
        let metadata = [
            item("a", timestamp: 100, width: 4_000, height: 3_000),
            item("b", timestamp: 300, width: 1_920, height: 1_080)
        ]

        XCTAssertTrue(
            DuplicateCandidateFilter.candidateIdentifiers(from: metadata, excluding: []).isEmpty
        )
    }

    func testExcludedAssetDoesNotCreateCandidatePair() {
        let metadata = [item("a", timestamp: 100), item("b", timestamp: 101)]

        XCTAssertTrue(
            DuplicateCandidateFilter.candidateIdentifiers(from: metadata, excluding: ["a"]).isEmpty
        )
    }

    func testSimilarHashRulesRemainStable() {
        let left = record("a", hash: 0)
        let close = record("b", hash: 0b1111)
        let far = record("c", hash: .max)

        XCTAssertTrue(DuplicateSimilarityEngine.isSimilar(left, close))
        XCTAssertFalse(DuplicateSimilarityEngine.isSimilar(left, far))
    }

    private func item(
        _ identifier: String,
        timestamp: TimeInterval?,
        width: Int = 4_032,
        height: Int = 3_024,
        burst: String? = nil,
        screenshot: Bool = false
    ) -> DuplicateAssetMetadata {
        DuplicateAssetMetadata(
            identifier: identifier,
            creationTimestamp: timestamp,
            pixelWidth: width,
            pixelHeight: height,
            burstIdentifier: burst,
            isScreenshot: screenshot
        )
    }

    private func record(_ identifier: String, hash: UInt64) -> DuplicateAnalysisRecord {
        DuplicateAnalysisRecord(
            identifier: identifier,
            pixelWidth: 4_032,
            pixelHeight: 3_024,
            creationTimestamp: 100,
            modificationTimestamp: nil,
            burstIdentifier: nil,
            differenceHash: hash,
            averageRed: 100,
            averageGreen: 100,
            averageBlue: 100
        )
    }
}
