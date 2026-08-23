import Foundation
import ImageIO
import Photos
import UIKit
import Vision

@MainActor
final class DuplicateAnalysisService: ObservableObject {
    @Published private(set) var groups: [DuplicatePhotoGroup] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var analyzedCount = 0
    @Published private(set) var totalCount = 0
    @Published var errorMessage: String?

    private struct Cache: Codable {
        let libraryFingerprint: String
        let groups: [DuplicatePhotoGroup]
        let lightweightRecords: [LightweightRecord]
    }

    private struct LightweightRecord: Codable, Sendable {
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
        let creationTimestamp: TimeInterval?
        let modificationTimestamp: TimeInterval?
        let burstIdentifier: String?
        let differenceHash: UInt64

        func matches(_ asset: PHAsset) -> Bool {
            pixelWidth == asset.pixelWidth &&
                pixelHeight == asset.pixelHeight &&
                modificationTimestamp == asset.modificationDate?.timeIntervalSince1970
        }
    }

    private struct FeatureDescriptor: Sendable {
        let identifier: String
        let archivedObservation: Data
    }

    private struct CandidatePair: Hashable, Sendable {
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
    }

    private struct HashBand: Hashable {
        let index: Int
        let value: UInt16
    }

    private let defaults: UserDefaults
    private let cacheKey = "duplicateAnalysis.cache.v2"
    private var cachedFingerprint: String?
    private var cachedLightweightRecords: [String: LightweightRecord] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: cacheKey),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            cachedFingerprint = cache.libraryFingerprint
            groups = cache.groups
            cachedLightweightRecords = Dictionary(
                uniqueKeysWithValues: cache.lightweightRecords.map { ($0.identifier, $0) }
            )
        }
    }

    func analyzeIfNeeded(
        library: PhotoLibraryService,
        pendingDeletions: PendingDeletionStore,
        force: Bool = false
    ) async {
        guard !isAnalyzing else { return }
        library.refreshAuthorizationStatus()
        guard library.canReadLibrary else { return }

        let assets = library.fetchImageAssets().filter {
            !pendingDeletions.contains(assetIdentifier: $0.localIdentifier)
        }
        let fingerprint = libraryFingerprint(for: assets)
        if !force, cachedFingerprint == fingerprint { return }

        isAnalyzing = true
        analyzedCount = 0
        totalCount = assets.count
        errorMessage = nil
        defer { isAnalyzing = false }

        var lightweightRecords: [LightweightRecord] = []
        lightweightRecords.reserveCapacity(assets.count)

        for asset in assets {
            if Task.isCancelled { return }
            if !force,
               let cached = cachedLightweightRecords[asset.localIdentifier],
               cached.matches(asset) {
                lightweightRecords.append(cached)
            } else if let image = await requestImage(
                for: asset,
                manager: library.imageManager,
                targetSize: CGSize(width: 48, height: 48)
            ), let differenceHash = Self.differenceHash(for: image) {
                lightweightRecords.append(
                    LightweightRecord(
                        identifier: asset.localIdentifier,
                        pixelWidth: asset.pixelWidth,
                        pixelHeight: asset.pixelHeight,
                        creationTimestamp: asset.creationDate?.timeIntervalSince1970,
                        modificationTimestamp: asset.modificationDate?.timeIntervalSince1970,
                        burstIdentifier: asset.burstIdentifier,
                        differenceHash: differenceHash
                    )
                )
            }
            analyzedCount += 1
        }

        let candidatePairs = await Self.makeCandidatePairs(lightweightRecords)
        let candidateIdentifiers = Set(candidatePairs.flatMap {
            [$0.leftIdentifier, $0.rightIdentifier]
        })
        let assetsByIdentifier = Dictionary(
            uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) }
        )

        var featureDescriptors: [FeatureDescriptor] = []
        featureDescriptors.reserveCapacity(candidateIdentifiers.count)
        for identifier in candidateIdentifiers.sorted() {
            if Task.isCancelled { return }
            guard let asset = assetsByIdentifier[identifier],
                  let image = await requestImage(
                    for: asset,
                    manager: library.imageManager,
                    targetSize: CGSize(width: 160, height: 160)
                  ),
                  let cgImage = image.cgImage,
                  let archivedObservation = await Self.makeFeaturePrint(
                    cgImage: cgImage,
                    orientation: Self.cgOrientation(from: image.imageOrientation)
                  ) else { continue }
            featureDescriptors.append(
                FeatureDescriptor(
                    identifier: identifier,
                    archivedObservation: archivedObservation
                )
            )
        }

        let nextGroups = await Self.groupSimilarPhotos(
            featureDescriptors,
            candidatePairs: candidatePairs
        )
        groups = nextGroups
        cachedFingerprint = fingerprint
        cachedLightweightRecords = Dictionary(
            uniqueKeysWithValues: lightweightRecords.map { ($0.identifier, $0) }
        )
        persist(
            fingerprint: fingerprint,
            groups: nextGroups,
            lightweightRecords: lightweightRecords
        )
    }

    func removeGroup(_ groupIdentifier: String) {
        groups.removeAll { $0.id == groupIdentifier }
        guard let cachedFingerprint else { return }
        persist(
            fingerprint: cachedFingerprint,
            groups: groups,
            lightweightRecords: Array(cachedLightweightRecords.values)
        )
    }

    private func requestImage(
        for asset: PHAsset,
        manager: PHCachingImageManager,
        targetSize: CGSize
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.version = .current
            options.isNetworkAccessAllowed = true
            manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                continuation.resume(returning: image)
            }
        }
    }

    private func libraryFingerprint(for assets: [PHAsset]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for asset in assets.sorted(by: { $0.localIdentifier < $1.localIdentifier }) {
            for byte in asset.localIdentifier.utf8 {
                hash ^= UInt64(byte)
                hash &*= 1_099_511_628_211
            }
            let modification = UInt64(asset.modificationDate?.timeIntervalSince1970 ?? 0)
            hash ^= modification
            hash &*= 1_099_511_628_211
        }
        return "v2|\(assets.count)|\(String(hash, radix: 16))"
    }

    private func persist(
        fingerprint: String,
        groups: [DuplicatePhotoGroup],
        lightweightRecords: [LightweightRecord]
    ) {
        guard let data = try? JSONEncoder().encode(
            Cache(
                libraryFingerprint: fingerprint,
                groups: groups,
                lightweightRecords: lightweightRecords
            )
        ) else { return }
        defaults.set(data, forKey: cacheKey)
    }

    private static func differenceHash(for image: UIImage) -> UInt64? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 9
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        var bit: UInt64 = 1
        for row in 0..<height {
            for column in 0..<(width - 1) {
                if pixels[row * width + column] > pixels[row * width + column + 1] {
                    hash |= bit
                }
                bit <<= 1
            }
        }
        return hash
    }

    private nonisolated static func makeCandidatePairs(
        _ records: [LightweightRecord]
    ) async -> Set<CandidatePair> {
        await Task.detached(priority: .utility) {
            guard records.count > 1 else { return [] }
            var pairs: Set<CandidatePair> = []
            var buckets: [HashBand: [Int]] = [:]

            // Four hash bands keep candidate lookup close to O(n), rather than all-pairs O(n²).
            for index in records.indices {
                let record = records[index]
                for bandIndex in 0..<4 {
                    let value = UInt16(truncatingIfNeeded: record.differenceHash >> (bandIndex * 16))
                    let key = HashBand(index: bandIndex, value: value)
                    for otherIndex in buckets[key, default: []].suffix(80) {
                        let other = records[otherIndex]
                        guard compatibleAspectRatios(record, other),
                              (record.differenceHash ^ other.differenceHash).nonzeroBitCount <= 10 else {
                            continue
                        }
                        pairs.insert(CandidatePair(record.identifier, other.identifier))
                    }
                    buckets[key, default: []].append(index)
                }
            }

            // Nearby captures and burst sequences survive small framing changes.
            let dated = records.indices.compactMap { index -> (Int, TimeInterval)? in
                guard let timestamp = records[index].creationTimestamp else { return nil }
                return (index, timestamp)
            }.sorted { $0.1 < $1.1 }
            for position in dated.indices {
                let left = records[dated[position].0]
                let upperBound = min(position + 25, dated.count)
                guard position + 1 < upperBound else { continue }
                for nextPosition in (position + 1)..<upperBound {
                    let delta = dated[nextPosition].1 - dated[position].1
                    if delta > 20 * 60 { break }
                    let right = records[dated[nextPosition].0]
                    guard compatibleAspectRatios(left, right),
                          (left.differenceHash ^ right.differenceHash).nonzeroBitCount <= 18 else {
                        continue
                    }
                    pairs.insert(CandidatePair(left.identifier, right.identifier))
                }
            }

            let bursts = Dictionary(grouping: records.filter { $0.burstIdentifier != nil }) {
                $0.burstIdentifier!
            }
            for burst in bursts.values where burst.count > 1 {
                for leftIndex in 0..<(burst.count - 1) {
                    for rightIndex in (leftIndex + 1)..<burst.count {
                        pairs.insert(CandidatePair(burst[leftIndex].identifier, burst[rightIndex].identifier))
                    }
                }
            }
            return pairs
        }.value
    }

    private nonisolated static func compatibleAspectRatios(
        _ left: LightweightRecord,
        _ right: LightweightRecord
    ) -> Bool {
        guard left.pixelHeight > 0, right.pixelHeight > 0 else { return false }
        let leftRatio = Double(left.pixelWidth) / Double(left.pixelHeight)
        let rightRatio = Double(right.pixelWidth) / Double(right.pixelHeight)
        return abs(leftRatio - rightRatio) <= 0.1
    }

    private nonisolated static func makeFeaturePrint(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async -> Data? {
        await Task.detached(priority: .utility) {
            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .scaleFit
            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
                options: [:]
            )
            do {
                try handler.perform([request])
                guard let observation = request.results?.first else { return nil }
                return try NSKeyedArchiver.archivedData(
                    withRootObject: observation,
                    requiringSecureCoding: true
                )
            } catch {
                return nil
            }
        }.value
    }

    private nonisolated static func groupSimilarPhotos(
        _ descriptors: [FeatureDescriptor],
        candidatePairs: Set<CandidatePair>
    ) async -> [DuplicatePhotoGroup] {
        await Task.detached(priority: .utility) {
            guard descriptors.count > 1 else { return [] }
            let indexByIdentifier = Dictionary(
                uniqueKeysWithValues: descriptors.enumerated().map { ($0.element.identifier, $0.offset) }
            )
            let observations: [VNFeaturePrintObservation?] = descriptors.map {
                try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self,
                    from: $0.archivedObservation
                )
            }
            var unionFind = UnionFind(count: descriptors.count)

            for pair in candidatePairs {
                guard let leftIndex = indexByIdentifier[pair.leftIdentifier],
                      let rightIndex = indexByIdentifier[pair.rightIdentifier],
                      let leftObservation = observations[leftIndex],
                      let rightObservation = observations[rightIndex] else { continue }
                var distance: Float = 0
                do {
                    try leftObservation.computeDistance(&distance, to: rightObservation)
                    if distance <= 8.0 { unionFind.union(leftIndex, rightIndex) }
                } catch {
                    continue
                }
            }

            var identifiersByRoot: [Int: [String]] = [:]
            for index in descriptors.indices {
                identifiersByRoot[unionFind.find(index), default: []]
                    .append(descriptors[index].identifier)
            }
            return identifiersByRoot.values
                .filter { $0.count >= 2 }
                .map(DuplicatePhotoGroup.init(assetIdentifiers:))
                .sorted {
                    if $0.count == $1.count { return $0.id < $1.id }
                    return $0.count > $1.count
                }
        }.value
    }

    private nonisolated static func cgOrientation(
        from orientation: UIImage.Orientation
    ) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

private struct UnionFind {
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
