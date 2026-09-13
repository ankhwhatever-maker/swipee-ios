import Foundation
import Photos
import UIKit

@MainActor
final class DuplicateAnalysisService: ObservableObject {
    @Published private(set) var groups: [DuplicatePhotoGroup] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var analyzedCount = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var indexedCount = 0
    @Published private(set) var unavailableCount = 0
    @Published var errorMessage: String?

    private struct Cache: Codable, Sendable {
        let version: Int
        let records: [DuplicateAnalysisRecord]
        let pairs: [DuplicateSimilarPair]
        let groups: [DuplicatePhotoGroup]
    }

    private struct Signature: Sendable {
        let differenceHash: UInt64
        let averageRed: UInt8
        let averageGreen: UInt8
        let averageBlue: UInt8
    }

    private let cacheURL: URL
    private let defaults: UserDefaults
    private let cacheWriter = CacheWriter()
    private var cacheLoadTask: Task<LoadedState?, Never>?
    private var didLoadCache = false
    private var records: [String: DuplicateAnalysisRecord] = [:]
    private var similarPairs: Set<DuplicateSimilarPair> = []
    private var cacheRevision = 0

    private static let automaticUnavailableRetryKey = "duplicateAnalysis.lastUnavailableRetry"
    private static let automaticUnavailableRetryInterval: TimeInterval = 24 * 60 * 60
    private static let checkpointBatchSize = 25

    private struct LoadedState: Sendable {
        let records: [String: DuplicateAnalysisRecord]
        let pairs: Set<DuplicateSimilarPair>
        let groups: [DuplicatePhotoGroup]
    }

    private actor CacheWriter {
        private var latestRevision = 0

        func write(_ cache: Cache, revision: Int, to url: URL) throws {
            guard revision >= latestRevision else { return }
            latestRevision = revision
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(cache)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }
    }

    init(defaults: UserDefaults = .standard, cacheURL: URL? = nil) {
        self.defaults = defaults
        self.cacheURL = cacheURL ?? Self.defaultCacheURL()
        let sourceURL = self.cacheURL
        cacheLoadTask = Task.detached(priority: .utility) {
            Self.loadState(cacheURL: sourceURL)
        }
    }

    func loadCachedResults() async {
        await ensureCacheLoaded()
    }

    func analyzeAutomaticallyIfNeeded(
        library: PhotoLibraryService,
        pendingDeletions: PendingDeletionStore
    ) async {
        let now = Date().timeIntervalSince1970
        let lastRetry = defaults.double(forKey: Self.automaticUnavailableRetryKey)
        let shouldRetryUnavailable = lastRetry == 0 ||
            now - lastRetry >= Self.automaticUnavailableRetryInterval
        let completed = await analyzeIfNeeded(
            library: library,
            pendingDeletions: pendingDeletions,
            retryUnavailable: shouldRetryUnavailable
        )
        if completed, shouldRetryUnavailable {
            defaults.set(now, forKey: Self.automaticUnavailableRetryKey)
        }
    }

    @discardableResult
    func analyzeIfNeeded(
        library: PhotoLibraryService,
        pendingDeletions: PendingDeletionStore,
        retryUnavailable: Bool = false
    ) async -> Bool {
        await ensureCacheLoaded()
        library.refreshAuthorizationStatus()
        guard library.canReadLibrary, !isAnalyzing, !Task.isCancelled else { return false }

        isAnalyzing = true
        analyzedCount = 0
        totalCount = 0
        errorMessage = nil
        defer { isAnalyzing = false }

        let pending = pendingDeletions.assetIdentifiers
        let allAssets = await library.fetchAllImageAssets()
        guard !Task.isCancelled else { return false }
        let metadata = allAssets.map {
            DuplicateAssetMetadata(
                identifier: $0.localIdentifier,
                creationTimestamp: $0.creationDate?.timeIntervalSince1970,
                pixelWidth: $0.pixelWidth,
                pixelHeight: $0.pixelHeight,
                burstIdentifier: $0.burstIdentifier,
                isScreenshot: $0.mediaSubtypes.contains(.photoScreenshot)
            )
        }
        let metadataCandidateIdentifiers = await Task.detached(priority: .utility) {
            DuplicateCandidateFilter.candidateIdentifiers(from: metadata, excluding: pending)
        }.value
        let assets = allAssets.filter { asset in
            guard metadataCandidateIdentifiers.contains(asset.localIdentifier) else { return false }
            guard let record = records[asset.localIdentifier] else { return true }
            return !record.matches(asset) || (retryUnavailable && !record.isAvailable)
        }
        totalCount = assets.count

        // Records outside the current metadata candidate set are stale: the asset was
        // deleted, excluded, modified out of candidacy, or is no longer near a peer.
        let staleIdentifiers = Set(records.keys).subtracting(metadataCandidateIdentifiers)

        await process(
            assets: assets,
            deleting: staleIdentifiers,
            manager: library.imageManager
        )
        updateCounts()
        return !Task.isCancelled
    }

    func removeGroup(_ groupIdentifier: String) {
        guard let group = groups.first(where: { $0.id == groupIdentifier }) else { return }
        let identifiers = Set(group.assetIdentifiers)
        similarPairs = similarPairs.filter {
            !(identifiers.contains($0.leftIdentifier) && identifiers.contains($0.rightIdentifier))
        }
        groups.removeAll { $0.id == groupIdentifier }
        persist()
    }

    private func process(
        assets: [PHAsset],
        deleting deletedIdentifiers: Set<String>,
        manager: PHCachingImageManager
    ) async {
        guard !assets.isEmpty || !deletedIdentifiers.isEmpty else { return }

        if !deletedIdentifiers.isEmpty {
            for identifier in deletedIdentifiers { records.removeValue(forKey: identifier) }
            await rebuildSimilarityResults(affectedIdentifiers: deletedIdentifiers)
            await persistAndWait()
            guard !Task.isCancelled else { return }
        }

        var batchStart = 0
        while batchStart < assets.count {
            let batchEnd = min(batchStart + Self.checkpointBatchSize, assets.count)
            var affectedIdentifiers: Set<String> = []

            for asset in assets[batchStart..<batchEnd] {
                guard !Task.isCancelled else { break }
                let identifier = asset.localIdentifier
                affectedIdentifiers.insert(identifier)
                let image = await requestSmallImage(for: asset, manager: manager)
                let signature: Signature?
                if let image {
                    signature = await Self.signature(for: image)
                } else {
                    signature = nil
                }
                records[identifier] = DuplicateAnalysisRecord(
                    identifier: identifier,
                    pixelWidth: asset.pixelWidth,
                    pixelHeight: asset.pixelHeight,
                    creationTimestamp: asset.creationDate?.timeIntervalSince1970,
                    modificationTimestamp: asset.modificationDate?.timeIntervalSince1970,
                    burstIdentifier: asset.burstIdentifier,
                    differenceHash: signature?.differenceHash,
                    averageRed: signature?.averageRed,
                    averageGreen: signature?.averageGreen,
                    averageBlue: signature?.averageBlue
                )
                analyzedCount += 1
            }

            if !affectedIdentifiers.isEmpty {
                await rebuildSimilarityResults(affectedIdentifiers: affectedIdentifiers)
                await persistAndWait()
            }
            guard !Task.isCancelled else { return }
            batchStart = batchEnd
        }
    }

    private func rebuildSimilarityResults(affectedIdentifiers: Set<String>) async {
        similarPairs = similarPairs.filter { !$0.contains(any: affectedIdentifiers) }
        var newPairs = await DuplicateSimilarityEngine.findSimilarPairs(
            records: Array(records.values),
            involving: affectedIdentifiers
        )
        let candidateIdentifiers = Set(newPairs.flatMap {
            [$0.leftIdentifier, $0.rightIdentifier]
        })
        if !candidateIdentifiers.isEmpty {
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: Array(candidateIdentifiers),
                options: nil
            )
            var availableCandidateIdentifiers: Set<String> = []
            result.enumerateObjects { asset, _, _ in
                availableCandidateIdentifiers.insert(asset.localIdentifier)
            }
            let missingIdentifiers = candidateIdentifiers.subtracting(availableCandidateIdentifiers)
            for identifier in missingIdentifiers { records.removeValue(forKey: identifier) }
            newPairs = newPairs.filter { !$0.contains(any: missingIdentifiers) }
            similarPairs = similarPairs.filter { !$0.contains(any: missingIdentifiers) }
        }
        similarPairs.formUnion(newPairs)
        groups = await DuplicateSimilarityEngine.makeGroups(
            pairs: similarPairs,
            validIdentifiers: Set(records.keys)
        )
        updateCounts()
    }

    private func requestSmallImage(
        for asset: PHAsset,
        manager: PHCachingImageManager
    ) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.resizeMode = .fast
            options.version = .current
            options.isNetworkAccessAllowed = false
            manager.requestImage(
                for: asset,
                targetSize: CGSize(width: 48, height: 48),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private func persist() {
        let snapshot = cacheSnapshot()
        Task {
            do {
                try await cacheWriter.write(snapshot.cache, revision: snapshot.revision, to: snapshot.url)
            } catch {
                errorMessage = "解析結果を保存できませんでした。次回、もう一度写真を確認します。"
            }
        }
    }

    private func persistAndWait() async {
        let snapshot = cacheSnapshot()
        do {
            try await cacheWriter.write(snapshot.cache, revision: snapshot.revision, to: snapshot.url)
        } catch {
            errorMessage = "解析結果を保存できませんでした。次回、もう一度写真を確認します。"
        }
    }

    private func cacheSnapshot() -> (cache: Cache, revision: Int, url: URL) {
        cacheRevision &+= 1
        return (
            Cache(
                version: 2,
                records: Array(records.values),
                pairs: Array(similarPairs),
                groups: groups
            ),
            cacheRevision,
            cacheURL
        )
    }

    private func ensureCacheLoaded() async {
        guard !didLoadCache else { return }
        let loaded = await cacheLoadTask?.value
        cacheLoadTask = nil
        didLoadCache = true
        guard let loaded else {
            updateCounts()
            return
        }
        records = loaded.records
        similarPairs = loaded.pairs
        groups = loaded.groups
        updateCounts()
    }

    private func updateCounts() {
        indexedCount = records.count
        unavailableCount = records.values.filter { !$0.isAvailable }.count
    }

    private nonisolated static func signature(for image: UIImage) async -> Signature? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .utility) {
            let width = 9
            let height = 8
            let bytesPerPixel = 4
            var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
            guard let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * bytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            var hash: UInt64 = 0
            var bit: UInt64 = 1
            var redTotal = 0
            var greenTotal = 0
            var blueTotal = 0
            for row in 0..<height {
                for column in 0..<width {
                    let offset = (row * width + column) * bytesPerPixel
                    redTotal += Int(pixels[offset])
                    greenTotal += Int(pixels[offset + 1])
                    blueTotal += Int(pixels[offset + 2])
                    guard column < width - 1 else { continue }
                    let nextOffset = offset + bytesPerPixel
                    let luminance = Int(pixels[offset]) * 30 + Int(pixels[offset + 1]) * 59 + Int(pixels[offset + 2]) * 11
                    let nextLuminance = Int(pixels[nextOffset]) * 30 + Int(pixels[nextOffset + 1]) * 59 + Int(pixels[nextOffset + 2]) * 11
                    if luminance > nextLuminance { hash |= bit }
                    bit <<= 1
                }
            }
            let count = width * height
            return Signature(
                differenceHash: hash,
                averageRed: UInt8(redTotal / count),
                averageGreen: UInt8(greenTotal / count),
                averageBlue: UInt8(blueTotal / count)
            )
        }.value
    }

    private nonisolated static func loadState(
        cacheURL: URL
    ) -> LoadedState? {
        if let data = try? Data(contentsOf: cacheURL),
           let cache = try? PropertyListDecoder().decode(Cache.self, from: data),
           cache.version == 2 {
            return LoadedState(
                records: Dictionary(uniqueKeysWithValues: cache.records.map { ($0.identifier, $0) }),
                pairs: Set(cache.pairs),
                groups: cache.groups
            )
        }
        return nil
    }

    private static func defaultCacheURL() -> URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Swipee", isDirectory: true)
        return directory.appendingPathComponent("duplicate-analysis.plist")
    }
}
