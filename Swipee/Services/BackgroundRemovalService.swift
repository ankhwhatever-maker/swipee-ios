import CoreImage
import Foundation
import ImageIO
@preconcurrency import Photos
import UIKit
@preconcurrency import Vision

struct BackgroundRemovalResult {
    let originalData: Data
    let cutoutPNGData: Data

    var originalImage: UIImage? { UIImage(data: originalData) }
    var cutoutImage: UIImage? { UIImage(data: cutoutPNGData) }
}

enum BackgroundRemovalService {
    static func process(asset: PHAsset) async throws -> BackgroundRemovalResult {
        let originalData = try await imageData(for: asset)
        let cutoutPNGData = try await Task.detached(priority: .userInitiated) {
            try removeBackground(from: originalData)
        }.value
        return BackgroundRemovalResult(
            originalData: originalData,
            cutoutPNGData: cutoutPNGData
        )
    }

    static func save(_ result: BackgroundRemovalResult, sourceAsset: PHAsset) async throws {
        let creationDate = sourceAsset.creationDate
        let location = sourceAsset.location
        let resources = PHAssetResource.assetResources(for: sourceAsset)
        let sourceName = resources.first(where: { $0.type == .fullSizePhoto })?.originalFilename
            ?? resources.first(where: { $0.type == .photo })?.originalFilename
            ?? "Swipee"
        let baseName = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent

        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = creationDate
            request.location = location
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = "\(baseName)-背景削除.png"
            request.addResource(with: .photo, data: result.cutoutPNGData, options: options)
        }
    }

    private static func imageData(for asset: PHAsset) async throws -> Data {
        let manager = PHImageManager.default()
        let request = BackgroundImageDataRequest()
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
                        continuation.resume(throwing: BackgroundRemovalError.imageUnavailable)
                    }
                }
                request.register(requestID, manager: manager)
            }
        } onCancel: {
            request.cancel(using: manager)
        }
    }

    private static func removeBackground(from data: Data) throws -> Data {
        guard let inputImage = CIImage(
            data: data,
            options: [.applyOrientationProperty: true]
        ) else {
            throw BackgroundRemovalError.imageUnavailable
        }

        let context = CIContext(options: [.cacheIntermediates: false])
        guard let inputCGImage = context.createCGImage(inputImage, from: inputImage.extent) else {
            throw BackgroundRemovalError.renderingFailed
        }

        let handler = VNImageRequestHandler(cgImage: inputCGImage, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw BackgroundRemovalError.subjectUnavailable
        }

        let maskedBuffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: false
        )
        let cutoutImage = CIImage(cvPixelBuffer: maskedBuffer)
        guard let cutoutCGImage = context.createCGImage(cutoutImage, from: cutoutImage.extent),
              let pngData = UIImage(cgImage: cutoutCGImage).pngData() else {
            throw BackgroundRemovalError.renderingFailed
        }
        return pngData
    }
}

private enum BackgroundRemovalError: LocalizedError {
    case imageUnavailable
    case subjectUnavailable
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return "写真を取得できませんでした。iCloudまたは写真へのアクセスを確認してください。"
        case .subjectUnavailable:
            return "背景から切り抜ける被写体を見つけられませんでした。"
        case .renderingFailed:
            return "背景を削除した画像を作成できませんでした。"
        }
    }
}

private final class BackgroundImageDataRequest: @unchecked Sendable {
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
