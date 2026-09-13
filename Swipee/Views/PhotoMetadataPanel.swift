import CoreLocation
import Photos
import SwiftUI

@MainActor
private enum PhotoPlaceNameCache {
    static let values: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 200
        return cache
    }()
}

@MainActor
private enum PhotoDataSizeCache {
    static let values: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 200
        return cache
    }()
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

struct PhotoMetadataPanel: View {
    let asset: PHAsset

    @State private var placeName = "-"
    @State private var dataSize: Int64?
    private let panelBackground = Color(red: 0.17, green: 0.17, blue: 0.16)

    var body: some View {
        ZStack {
            metadataBackground

            VStack(spacing: 12) {
                Spacer(minLength: 100)

                HStack(spacing: 12) {
                    metadataTile(
                        title: "サイズ",
                        value: formattedDataSize,
                        icon: "photo"
                    )
                    metadataTile(
                        title: "撮影された日時",
                        value: formattedCreationDate,
                        icon: "calendar"
                    )
                }

                if asset.location != nil {
                    metadataTile(
                        title: "場所",
                        value: placeName,
                        icon: "mappin"
                    )
                }
            }
            .padding(18)
        }
        .contentShape(Rectangle())
        .task(id: asset.localIdentifier) {
            await loadPlaceName()
        }
        .task(id: asset.localIdentifier) {
            await loadDataSize()
        }
    }

    private var metadataBackground: some View {
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(
                colors: [.clear, panelBackground.opacity(0.72), panelBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 110)
            panelBackground
                .frame(height: asset.location == nil ? 128 : 232)
        }
        .ignoresSafeArea()
    }

    private func metadataTile(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 92)
        .padding(.horizontal, 10)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
    }

    private var formattedCreationDate: String {
        guard let date = asset.creationDate else { return "-" }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else { return "-" }
        return String(format: "%04d/%02d/%02d", year, month, day)
    }

    private var formattedDataSize: String {
        guard let bytes = dataSize else { return "-" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var preferredDataSizeResources: [PHAssetResource] {
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

    private func loadDataSize() async {
        dataSize = nil
        let cacheKey = asset.localIdentifier as NSString
        if let cachedValue = PhotoDataSizeCache.values.object(forKey: cacheKey) {
            dataSize = cachedValue.int64Value
            return
        }

        do {
            var total: Int64 = 0
            for resource in preferredDataSizeResources {
                try Task.checkCancellation()
                total += try await dataSize(of: resource)
            }
            guard !Task.isCancelled, total > 0 else { return }
            dataSize = total
            PhotoDataSizeCache.values.setObject(NSNumber(value: total), forKey: cacheKey)
        } catch {
            guard !Task.isCancelled else { return }
            dataSize = nil
        }
    }

    private func dataSize(of resource: PHAssetResource) async throws -> Int64 {
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

    private func loadPlaceName() async {
        if let cachedValue = PhotoPlaceNameCache.values.object(forKey: asset.localIdentifier as NSString) {
            placeName = cachedValue as String
            return
        }

        guard let location = asset.location else {
            placeName = "-"
            PhotoPlaceNameCache.values.setObject(placeName as NSString, forKey: asset.localIdentifier as NSString)
            return
        }

        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                location,
                preferredLocale: Locale(identifier: "ja_JP")
            )
            guard !Task.isCancelled, let placemark = placemarks.first else { return }
            let components = [placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            placeName = components.isEmpty ? "-" : components.joined(separator: "、")
            PhotoPlaceNameCache.values.setObject(placeName as NSString, forKey: asset.localIdentifier as NSString)
        } catch {
            guard !Task.isCancelled else { return }
            placeName = "-"
        }
    }
}
