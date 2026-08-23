import Photos
import UIKit

@MainActor
final class PhotoLibraryService: ObservableObject {
    @Published private(set) var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published private(set) var candidates: [PHAsset] = []
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    let imageManager = PHCachingImageManager()
    private var cachedAssets: [PHAsset] = []

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
        refreshAuthorizationStatus()
        guard canReadLibrary else { candidates = []; return }
        isLoading = true
        defer { isLoading = false }

        if authorizationStatus == .authorized, !pendingDeletions.records.isEmpty {
            let availableIdentifiers = Set(
                fetchAssets(localIdentifiers: pendingDeletions.records.map(\.assetIdentifier))
                    .map(\.localIdentifier)
            )
            pendingDeletions.reconcile(validAssetIdentifiers: availableIdentifiers)
        }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let start = settings.period.startDate() { options.predicate = NSPredicate(format: "creationDate >= %@", start as NSDate) }
        let result = PHAsset.fetchAssets(with: options)
        var next: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            guard settings.includes(asset),
                  !pendingDeletions.contains(assetIdentifier: asset.localIdentifier),
                  !history.hasReviewed(assetIdentifier: asset.localIdentifier, conditionKey: settings.conditionKey) else {
                return
            }
            next.append(asset)
        }
        candidates = next
        updateCache(startingAt: 0)
    }

    func removeCandidate(_ asset: PHAsset) { candidates.removeAll { $0.localIdentifier == asset.localIdentifier } }

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

    func fetchImageAssets() -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func markFavorite(_ asset: PHAsset) async throws {
        try await setFavorite(asset, isFavorite: true)
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

    func updateCache(startingAt index: Int, targetSize: CGSize = CGSize(width: 900, height: 1200)) {
        if !cachedAssets.isEmpty { imageManager.stopCachingImages(for: cachedAssets, targetSize: targetSize, contentMode: .aspectFill, options: nil) }
        let end = min(index + 4, candidates.count)
        cachedAssets = index < end ? Array(candidates[index..<end]) : []
        if !cachedAssets.isEmpty { imageManager.startCachingImages(for: cachedAssets, targetSize: targetSize, contentMode: .aspectFill, options: nil) }
    }
}
