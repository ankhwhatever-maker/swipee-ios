import Foundation
@preconcurrency import Photos

@MainActor
final class PhotoAssetSizeService {
    static let shared = PhotoAssetSizeService()

    private let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 200
        return cache
    }()

    private init() {}

    func size(for asset: PHAsset) async throws -> Int64 {
        let cacheKey = asset.localIdentifier as NSString
        if let cachedValue = cache.object(forKey: cacheKey) {
            return cachedValue.int64Value
        }

        var total: Int64 = 0
        for resource in preferredResources(for: asset) {
            try Task.checkCancellation()
            total += try await size(of: resource)
        }

        guard total > 0 else {
            throw PhotoAssetSizeError.resourceUnavailable
        }
        cache.setObject(NSNumber(value: total), forKey: cacheKey)
        return total
    }

    func totalSize(for assets: [PHAsset]) async throws -> Int64 {
        var seenIdentifiers = Set<String>()
        var total: Int64 = 0

        for asset in assets where seenIdentifiers.insert(asset.localIdentifier).inserted {
            try Task.checkCancellation()
            total += try await size(for: asset)
        }
        return total
    }

    private func preferredResources(for asset: PHAsset) -> [PHAssetResource] {
        let resources = PHAssetResource.assetResources(for: asset)
        if asset.mediaType == .video {
            if let video = resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first(where: { $0.type == .video }) {
                return [video]
            }
            return []
        }

        if asset.mediaSubtypes.contains(.photoLive) {
            if let photo = resources.first(where: { $0.type == .fullSizePhoto }),
               let pairedVideo = resources.first(where: { $0.type == .fullSizePairedVideo }) {
                return [photo, pairedVideo]
            }
            if let photo = resources.first(where: { $0.type == .photo }),
               let pairedVideo = resources.first(where: { $0.type == .pairedVideo }) {
                return [photo, pairedVideo]
            }
            return []
        }

        if let photo = resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo }) {
            return [photo]
        }
        return []
    }

    private func size(of resource: PHAssetResource) async throws -> Int64 {
        let manager = PHAssetResourceManager.default()
        let request = PhotoResourceSizeRequest()
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = manager.requestData(
                    for: resource,
                    options: options,
                    dataReceivedHandler: { data in
                        request.add(data.count)
                    },
                    completionHandler: { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: request.total)
                        }
                    }
                )
                request.register(requestID, manager: manager)
            }
        } onCancel: {
            request.cancel(using: manager)
        }
    }
}

private enum PhotoAssetSizeError: Error {
    case resourceUnavailable
}

private final class PhotoResourceSizeRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: PHAssetResourceDataRequestID?
    private var isCancelled = false
    private var byteCount: Int64 = 0

    func add(_ count: Int) {
        lock.lock()
        byteCount += Int64(count)
        lock.unlock()
    }

    func register(_ requestID: PHAssetResourceDataRequestID, manager: PHAssetResourceManager) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()

        if shouldCancel {
            manager.cancelDataRequest(requestID)
        }
    }

    func cancel(using manager: PHAssetResourceManager) {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        lock.unlock()

        if let requestID {
            manager.cancelDataRequest(requestID)
        }
    }

    var total: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return byteCount
    }
}
