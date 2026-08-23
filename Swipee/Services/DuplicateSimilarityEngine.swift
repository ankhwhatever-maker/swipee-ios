import Foundation
import Photos

struct DuplicateAnalysisRecord: Codable, Sendable {
    let identifier: String
    let pixelWidth: Int
    let pixelHeight: Int
    let creationTimestamp: TimeInterval?
    let modificationTimestamp: TimeInterval?
    let burstIdentifier: String?
    let differenceHash: UInt64?
    let averageRed: UInt8?
    let averageGreen: UInt8?
    let averageBlue: UInt8?

    var isAvailable: Bool { differenceHash != nil }

    func matches(_ asset: PHAsset) -> Bool {
        pixelWidth == asset.pixelWidth &&
            pixelHeight == asset.pixelHeight &&
            modificationTimestamp == asset.modificationDate?.timeIntervalSince1970
    }
}

struct DuplicateSimilarPair: Codable, Hashable, Sendable {
    let leftIdentifier: String
    let rightIdentifier: String

    init(_ leftIdentifier: String, _ rightIdentifier: String) {
        if leftIdentifier < rightIdentifier {
            self.leftIdentifier = leftIdentifier
            self.rightIdentifier = rightIdentifier
        } else {
            self.leftIdentifier = rightIdentifier
            self.rightIdentifier = leftIdentifier
        }
    }

    func contains(any identifiers: Set<String>) -> Bool {
        identifiers.contains(leftIdentifier) || identifiers.contains(rightIdentifier)
    }
}

enum DuplicateSimilarityEngine {
    static func findSimilarPairs(
        records: [DuplicateAnalysisRecord],
        involving affectedIdentifiers: Set<String>
    ) async -> Set<DuplicateSimilarPair> {
        await Task.detached(priority: .utility) {
            let records = records.filter { $0.differenceHash != nil }
            guard records.count > 1 else { return [] }
            let affected = records.filter { affectedIdentifiers.contains($0.identifier) }
            let unaffected = records.filter { !affectedIdentifiers.contains($0.identifier) }
            var pairs: Set<DuplicateSimilarPair> = []
            for left in affected {
                for right in unaffected where isSimilar(left, right) {
                    pairs.insert(DuplicateSimilarPair(left.identifier, right.identifier))
                }
            }
            if affected.count > 1 {
                for leftIndex in 0..<(affected.count - 1) {
                    for rightIndex in (leftIndex + 1)..<affected.count {
                        let left = affected[leftIndex]
                        let right = affected[rightIndex]
                        if isSimilar(left, right) {
                            pairs.insert(DuplicateSimilarPair(left.identifier, right.identifier))
                        }
                    }
                }
            }
            return pairs
        }.value
    }

    static func isSimilar(_ left: DuplicateAnalysisRecord, _ right: DuplicateAnalysisRecord) -> Bool {
        guard let leftHash = left.differenceHash,
              let rightHash = right.differenceHash,
              left.pixelHeight > 0,
              right.pixelHeight > 0 else { return false }

        let leftRatio = Double(left.pixelWidth) / Double(left.pixelHeight)
        let rightRatio = Double(right.pixelWidth) / Double(right.pixelHeight)
        guard abs(leftRatio - rightRatio) <= 0.08 else { return false }

        let hashDistance = (leftHash ^ rightHash).nonzeroBitCount
        let colorDistance = averageColorDistance(left, right)
        if hashDistance <= 4, colorDistance <= 80 { return true }

        if let leftBurst = left.burstIdentifier,
           leftBurst == right.burstIdentifier,
           hashDistance <= 12,
           colorDistance <= 120 {
            return true
        }

        if let leftTime = left.creationTimestamp,
           let rightTime = right.creationTimestamp,
           abs(leftTime - rightTime) <= 10 * 60,
           hashDistance <= 8,
           colorDistance <= 100 {
            return true
        }
        return false
    }

    static func makeGroups(
        pairs: Set<DuplicateSimilarPair>,
        validIdentifiers: Set<String>
    ) async -> [DuplicatePhotoGroup] {
        await Task.detached(priority: .utility) {
            let identifiers = Array(Set(pairs.flatMap {
                [$0.leftIdentifier, $0.rightIdentifier]
            }).intersection(validIdentifiers)).sorted()
            guard identifiers.count > 1 else { return [] }
            let indexes = Dictionary(
                uniqueKeysWithValues: identifiers.enumerated().map { ($0.element, $0.offset) }
            )
            var unionFind = DuplicateUnionFind(count: identifiers.count)
            for pair in pairs {
                guard let left = indexes[pair.leftIdentifier],
                      let right = indexes[pair.rightIdentifier] else { continue }
                unionFind.union(left, right)
            }
            var members: [Int: [String]] = [:]
            for index in identifiers.indices {
                members[unionFind.find(index), default: []].append(identifiers[index])
            }
            return members.values
                .filter { $0.count > 1 }
                .map(DuplicatePhotoGroup.init(assetIdentifiers:))
                .sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
        }.value
    }

    private static func averageColorDistance(
        _ left: DuplicateAnalysisRecord,
        _ right: DuplicateAnalysisRecord
    ) -> Int {
        guard let leftRed = left.averageRed,
              let leftGreen = left.averageGreen,
              let leftBlue = left.averageBlue,
              let rightRed = right.averageRed,
              let rightGreen = right.averageGreen,
              let rightBlue = right.averageBlue else {
            return 0
        }
        return abs(Int(leftRed) - Int(rightRed)) +
            abs(Int(leftGreen) - Int(rightGreen)) +
            abs(Int(leftBlue) - Int(rightBlue))
    }
}

private struct DuplicateUnionFind {
    private var parents: [Int]
    private var ranks: [Int]

    init(count: Int) {
        parents = Array(0..<count)
        ranks = Array(repeating: 0, count: count)
    }

    mutating func find(_ value: Int) -> Int {
        if parents[value] != value { parents[value] = find(parents[value]) }
        return parents[value]
    }

    mutating func union(_ left: Int, _ right: Int) {
        let leftRoot = find(left)
        let rightRoot = find(right)
        guard leftRoot != rightRoot else { return }
        if ranks[leftRoot] < ranks[rightRoot] {
            parents[leftRoot] = rightRoot
        } else if ranks[leftRoot] > ranks[rightRoot] {
            parents[rightRoot] = leftRoot
        } else {
            parents[rightRoot] = leftRoot
            ranks[leftRoot] += 1
        }
    }
}
