import Foundation
@preconcurrency import Photos

enum PhotoImageDataService {
    static func loadCurrentData(for asset: PHAsset) async throws -> Data {
        let manager = PHImageManager.default()
        let request = PhotoImageDataRequest()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .current
        options.isNetworkAccessAllowed = true

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = manager.requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, info in
                    if let error = info?[PHImageErrorKey] as? Error {
                        continuation.resume(throwing: error)
                    } else if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: PhotoImageDataError.imageUnavailable)
                    }
                }
                request.register(requestID, manager: manager)
            }
        } onCancel: {
            request.cancel(using: manager)
        }
    }

    static func saveNewPhoto(
        data: Data,
        filenameSuffix: String,
        fileExtension: String,
        sourceAsset: PHAsset
    ) async throws {
        let resources = PHAssetResource.assetResources(for: sourceAsset)
        let sourceName = resources.first(where: { $0.type == .fullSizePhoto })?.originalFilename
            ?? resources.first(where: { $0.type == .photo })?.originalFilename
            ?? "Swipee"
        let baseName = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        let creationDate = sourceAsset.creationDate
        let location = sourceAsset.location

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = creationDate
            request.location = location
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "\(baseName)\(filenameSuffix).\(fileExtension)"
            request.addResource(with: .photo, data: data, options: options)
        }
    }
}

enum PhotoImageDataError: LocalizedError {
    case imageUnavailable

    var errorDescription: String? {
        "写真を取得できませんでした。iCloudまたは写真へのアクセスを確認してください。"
    }
}

private final class PhotoImageDataRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var requestID: PHImageRequestID?
    private var isCancelled = false

    func register(_ requestID: PHImageRequestID, manager: PHImageManager) {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled
        lock.unlock()

        if shouldCancel {
            manager.cancelImageRequest(requestID)
        }
    }

    func cancel(using manager: PHImageManager) {
        lock.lock()
        isCancelled = true
        let requestID = requestID
        lock.unlock()

        if let requestID {
            manager.cancelImageRequest(requestID)
        }
    }
}
