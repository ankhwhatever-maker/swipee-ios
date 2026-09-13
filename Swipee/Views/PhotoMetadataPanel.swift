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

struct PhotoMetadataPanel: View {
    let asset: PHAsset

    @State private var placeName = "-"
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
        guard let bytes = metadataDataSize else { return "-" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var metadataDataSize: Int64? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredResource = resources.first(where: { $0.type == .fullSizePhoto })
            ?? resources.first(where: { $0.type == .photo })
            ?? resources.first
        guard let preferredResource else { return nil }

        // dataSize is a public PhotoKit property on newer OS versions, but the
        // app still builds with an SDK where it isn't statically available.
        let selector = NSSelectorFromString("dataSize")
        guard preferredResource.responds(to: selector),
              let value = preferredResource.value(forKey: "dataSize") as? NSNumber,
              value.int64Value > 0 else { return nil }
        return value.int64Value
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
