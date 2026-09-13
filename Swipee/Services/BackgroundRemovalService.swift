import CoreImage
import Foundation
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
        let originalData = try await PhotoImageDataService.loadCurrentData(for: asset)
        let cutoutPNGData = try await Task.detached(priority: .userInitiated) {
            try removeBackground(from: originalData)
        }.value
        return BackgroundRemovalResult(
            originalData: originalData,
            cutoutPNGData: cutoutPNGData
        )
    }

    static func save(_ result: BackgroundRemovalResult, sourceAsset: PHAsset) async throws {
        try await PhotoImageDataService.saveNewPhoto(
            data: result.cutoutPNGData,
            filenameSuffix: "-背景削除",
            fileExtension: "png",
            sourceAsset: sourceAsset
        )
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
