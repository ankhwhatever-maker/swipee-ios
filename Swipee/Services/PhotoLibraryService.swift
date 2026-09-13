@preconcurrency import Photos
import UIKit

@MainActor
final class PhotoLibraryService: ObservableObject {
    @Published private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var candidates: [PHAsset] = []
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    let imageManager = PHCachingImageManager()
    private var cachedAssets: [PHAsset] = []
    private var reloadGeneration = 0
    private let deckCacheTargetSize = CGSize(width: 900, height: 1200)

    var canReadLibrary: Bool { authorizationStatus == .authorized || authorizationStatus == .limited }

    func refreshAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        authorizationStatus = status
    }

    func reload(
        settings: CandidateSettings,
        history: ReviewHistoryStore,
        pendingDeletions: PendingDeletionStore
    ) async {
        reloadGeneration &+= 1
        let generation = reloadGeneration
        refreshAuthorizationStatus()
        guard canReadLibrary else {
            candidates = []
            isLoading = false
            return
        }
        isLoading = true
        defer {
            if generation == reloadGeneration { isLoading = false }
        }

        if authorizationStatus == .authorized, !pendingDeletions.records.isEmpty {
            let availableIdentifiers = Set(
                fetchAssets(localIdentifiers: pendingDeletions.records.map(\.assetIdentifier))
                    .map(\.localIdentifier)
            )
            pendingDeletions.reconcile(validAssetIdentifiers: availableIdentifiers)
        }

        let pendingIdentifiers = pendingDeletions.assetIdentifiers
        let reviewedIdentifiers = history.assetIdentifiers(for: settings.conditionKey)
        let next = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let bounds = settings.dateBounds()
            var datePredicates: [NSPredicate] = []
            if let start = bounds.start {
                datePredicates.append(NSPredicate(format: "creationDate >= %@", start as NSDate))
            }
            if let end = bounds.endExclusive {
                datePredicates.append(NSPredicate(format: "creationDate < %@", end as NSDate))
            }
            if !datePredicates.isEmpty {
                options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: datePredicates)
            }
            let result = PHAsset.fetchAssets(with: options)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, stop in
                if Task.isCancelled {
                    stop.pointee = true
                    return
                }
                guard settings.includes(asset),
                      !pendingIdentifiers.contains(asset.localIdentifier),
                      !reviewedIdentifiers.contains(asset.localIdentifier) else { return }
                assets.append(asset)
            }
            return assets
        }.value
        guard !Task.isCancelled, generation == reloadGeneration else { return }
        candidates = next
        updateCache(startingAt: 0)
    }

    func removeCandidate(_ asset: PHAsset) {
        if candidates.first?.localIdentifier == asset.localIdentifier {
            candidates.removeFirst()
        } else if let index = candidates.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
            candidates.remove(at: index)
        }
        updateCache(startingAt: 0)
    }

    func restoreCandidate(_ asset: PHAsset) {
        guard !candidates.contains(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        candidates.insert(asset, at: 0)
        updateCache(startingAt: 0)
    }

    func fetchAssets(localIdentifiers: [String]) -> [PHAsset] {
        guard !localIdentifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assetsByIdentifier: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, _ in
            assetsByIdentifier[asset.localIdentifier] = asset
        }
        return localIdentifiers.compactMap { assetsByIdentifier[$0] }
    }

    func fetchAllImageAssets() async -> [PHAsset] {
        await Task.detached(priority: .utility) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let result = PHAsset.fetchAssets(with: .image, options: options)
            var assets: [PHAsset] = []
            assets.reserveCapacity(result.count)
            result.enumerateObjects { asset, _, stop in
                if Task.isCancelled {
                    stop.pointee = true
                } else {
                    assets.append(asset)
                }
            }
            return assets
        }.value
    }

    func setFavorite(_ asset: PHAsset, isFavorite: Bool) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = isFavorite
        }
    }

    func deleteAssets(_ assets: [PHAsset]) async throws {
        guard !assets.isEmpty else { return }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }

    nonisolated static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        // PHPhotosErrorUserCancelled
        return nsError.domain == PHPhotosErrorDomain && nsError.code == 3072
    }

    func updateCache(startingAt index: Int) {
        let end = min(index + 3, candidates.count)
        let nextAssets = index < end ? Array(candidates[index..<end]) : []
        let nextIdentifiers = Set(nextAssets.map(\.localIdentifier))
        let currentIdentifiers = Set(cachedAssets.map(\.localIdentifier))
        let removedAssets = cachedAssets.filter { !nextIdentifiers.contains($0.localIdentifier) }
        let addedAssets = nextAssets.filter { !currentIdentifiers.contains($0.localIdentifier) }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        if !removedAssets.isEmpty {
            imageManager.stopCachingImages(
                for: removedAssets,
                targetSize: deckCacheTargetSize,
                contentMode: .aspectFit,
                options: options
            )
        }
        if !addedAssets.isEmpty {
            imageManager.startCachingImages(
                for: addedAssets,
                targetSize: deckCacheTargetSize,
                contentMode: .aspectFit,
                options: options
            )
        }
        cachedAssets = nextAssets
    }
}
