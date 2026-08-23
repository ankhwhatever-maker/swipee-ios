import Foundation

struct DuplicateAssetMetadata: Sendable, Equatable {
    let identifier: String
    let creationTimestamp: TimeInterval?
    let pixelWidth: Int
    let pixelHeight: Int
    let burstIdentifier: String?
    let isScreenshot: Bool
}

enum DuplicateCandidateFilter {
    static func candidateIdentifiers(
        from metadata: [DuplicateAssetMetadata],
        excluding excludedIdentifiers: Set<String>
    ) -> Set<String> {
        let metadata = metadata.filter { !excludedIdentifiers.contains($0.identifier) }
        guard metadata.count > 1 else { return [] }

        var identifiers: Set<String> = []
        let burstGroups = Dictionary(grouping: metadata.compactMap { item in
            item.burstIdentifier.map { ($0, item.identifier) }
        }, by: \.0)
        for group in burstGroups.values where group.count > 1 {
            identifiers.formUnion(group.map(\.1))
        }

        let datedMetadata = metadata
            .compactMap { item -> (DuplicateAssetMetadata, TimeInterval)? in
                item.creationTimestamp.map { (item, $0) }
            }
            .sorted { $0.1 < $1.1 }

        for leftIndex in datedMetadata.indices {
            let (left, leftTimestamp) = datedMetadata[leftIndex]
            var rightIndex = datedMetadata.index(after: leftIndex)
            while rightIndex < datedMetadata.endIndex {
                let (right, rightTimestamp) = datedMetadata[rightIndex]
                let interval = rightTimestamp - leftTimestamp
                if interval > 120 { break }
                if isCandidate(left, right, interval: interval) {
                    identifiers.insert(left.identifier)
                    identifiers.insert(right.identifier)
                }
                rightIndex += 1
            }
        }
        return identifiers
    }

    static func isCandidate(
        _ left: DuplicateAssetMetadata,
        _ right: DuplicateAssetMetadata,
        interval: TimeInterval
    ) -> Bool {
        if let burstIdentifier = left.burstIdentifier,
           burstIdentifier == right.burstIdentifier {
            return true
        }
        let sameSize = left.pixelWidth == right.pixelWidth && left.pixelHeight == right.pixelHeight
        if interval <= 10, sameSize { return true }

        guard left.pixelHeight > 0, right.pixelHeight > 0 else { return false }
        let leftRatio = Double(left.pixelWidth) / Double(left.pixelHeight)
        let rightRatio = Double(right.pixelWidth) / Double(right.pixelHeight)
        let ratioDifference = abs(leftRatio - rightRatio)
        if interval <= 30, ratioDifference <= 0.015 { return true }

        return left.isScreenshot && right.isScreenshot &&
            interval <= 120 && ratioDifference <= 0.02
    }
}
