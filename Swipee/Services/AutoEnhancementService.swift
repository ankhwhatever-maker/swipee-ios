import CoreImage
import Foundation
import ImageIO
@preconcurrency import Photos
import UIKit

struct AutoEnhancementPreview {
    let originalJPEGData: Data
    let enhancedJPEGData: Data

    var originalImage: UIImage? { UIImage(data: originalJPEGData) }
    var enhancedImage: UIImage? { UIImage(data: enhancedJPEGData) }
}

enum AutoEnhancementService {
    private static let previewMaximumPixelSize = 1_800
    private static let jpegQuality: CGFloat = 0.95

    static func preview(asset: PHAsset) async throws -> AutoEnhancementPreview {
        let sourceData = try await PhotoImageDataService.loadCurrentData(for: asset)
        return try await Task.detached(priority: .userInitiated) {
            guard let previewImage = downsampledImage(
                from: sourceData,
                maximumPixelSize: previewMaximumPixelSize
            ),
            let originalData = UIImage(cgImage: previewImage).jpegData(compressionQuality: jpegQuality) else {
                throw AutoEnhancementError.imageUnavailable
            }
            let enhancedImage = try enhancedImage(from: previewImage)
            guard let enhancedData = UIImage(cgImage: enhancedImage).jpegData(compressionQuality: jpegQuality) else {
                throw AutoEnhancementError.renderingFailed
            }
            return AutoEnhancementPreview(
                originalJPEGData: originalData,
                enhancedJPEGData: enhancedData
            )
        }.value
    }

    static func saveEnhancedPhoto(sourceAsset: PHAsset) async throws {
        let sourceData = try await PhotoImageDataService.loadCurrentData(for: sourceAsset)
        let enhancedData = try await Task.detached(priority: .userInitiated) {
            guard let sourceImage = orientedImage(from: sourceData) else {
                throw AutoEnhancementError.imageUnavailable
            }
            let enhancedImage = try enhancedImage(from: sourceImage)
            guard let data = UIImage(cgImage: enhancedImage).jpegData(compressionQuality: jpegQuality) else {
                throw AutoEnhancementError.renderingFailed
            }
            return data
        }.value

        try await PhotoImageDataService.saveNewPhoto(
            data: enhancedData,
            filenameSuffix: "-自動補正",
            fileExtension: "jpg",
            sourceAsset: sourceAsset
        )
    }

    private static func downsampledImage(from data: Data, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func orientedImage(from data: Data) -> CGImage? {
        guard let image = CIImage(
            data: data,
            options: [.applyOrientationProperty: true]
        ) else { return nil }
        return CIContext(options: [.cacheIntermediates: false])
            .createCGImage(image, from: image.extent)
    }

    private static func enhancedImage(from sourceImage: CGImage) throws -> CGImage {
        let inputImage = CIImage(cgImage: sourceImage)
        var outputImage = inputImage
        let filters = inputImage.autoAdjustmentFilters(options: [
            .enhance: true,
            .redEye: true,
            .crop: false,
            .level: false
        ])

        for filter in filters {
            filter.setValue(outputImage, forKey: kCIInputImageKey)
            if let nextImage = filter.outputImage {
                outputImage = nextImage
            }
        }

        outputImage = outputImage.cropped(to: inputImage.extent)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        guard let renderedImage = CIContext(options: [.cacheIntermediates: false]).createCGImage(
            outputImage,
            from: inputImage.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        ) else {
            throw AutoEnhancementError.renderingFailed
        }
        return renderedImage
    }
}

private enum AutoEnhancementError: LocalizedError {
    case imageUnavailable
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable:
            return "写真を取得できませんでした。iCloudまたは写真へのアクセスを確認してください。"
        case .renderingFailed:
            return "自動補正した写真を作成できませんでした。"
        }
    }
}
