import Photos
import SwiftUI

enum AssetImageDisplayMode: Hashable {
    case fill
    case fit
}

struct AssetImageView: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    var displayMode: AssetImageDisplayMode = .fill
    var allowsNetworkAccess = true
    var showsVideoBadge = true

    @State private var image: UIImage?
    @State private var displayedPresentationKey: String?
    @State private var requestID: PHImageRequestID?
    @State private var requestGeneration = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                canvasBackground
                if let image { imageContent(image) }
                else { ProgressView() }
                if asset.mediaType == .video, showsVideoBadge {
                    VStack {
                        Spacer()
                        HStack {
                            Label(duration, systemImage: "video.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.swipeePhotoOverlay, in: Capsule())
                            Spacer()
                        }
                        .padding()
                    }
                }
            }
            .clipped()
            .task(id: requestKey(size: proxy.size)) { request(size: proxy.size) }
            .onDisappear {
                requestGeneration &+= 1
                if let requestID { manager.cancelImageRequest(requestID) }
                requestID = nil
            }
        }
    }

    @ViewBuilder
    private var canvasBackground: some View {
        if displayMode == .fit {
            Color.black
        } else {
            Color(.secondarySystemBackground)
        }
    }

    @ViewBuilder
    private func imageContent(_ image: UIImage) -> some View {
        if displayMode == .fit {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.28), radius: 10)
        } else {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        }
    }

    private var duration: String {
        let seconds = Int(asset.duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func requestKey(size: CGSize) -> String {
        "\(asset.localIdentifier)-\(displayMode)-\(allowsNetworkAccess)-\(Int(size.width))-\(Int(size.height))"
    }

    private func presentationKey(size: CGSize) -> String {
        "\(asset.localIdentifier)-\(displayMode)-\(Int(size.width))-\(Int(size.height))"
    }

    private func request(size: CGSize) {
        if let requestID { manager.cancelImageRequest(requestID) }
        requestGeneration &+= 1
        let generation = requestGeneration
        let requestedIdentifier = asset.localIdentifier
        let requestedPresentationKey = presentationKey(size: size)
        let keepsCurrentImage = image != nil && displayedPresentationKey == requestedPresentationKey
        let scale = UIScreen.main.scale
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = allowsNetworkAccess
        let contentMode: PHImageContentMode = displayMode == .fit ? .aspectFit : .aspectFill
        requestID = manager.requestImage(for: asset, targetSize: CGSize(width: size.width * scale, height: size.height * scale), contentMode: contentMode, options: options) { result, info in
            Task { @MainActor in
                guard generation == requestGeneration,
                      requestedIdentifier == asset.localIdentifier,
                      let result else { return }

                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                // When a waiting card becomes the top card, PhotoKit starts a
                // network-enabled request. Keep the already displayed thumbnail
                // instead of briefly replacing it with another degraded result.
                guard !(keepsCurrentImage && isDegraded) else { return }

                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    image = result
                    displayedPresentationKey = requestedPresentationKey
                }
            }
        }
    }
}
