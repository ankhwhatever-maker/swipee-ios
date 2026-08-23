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

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                canvasBackground
                if let image { imageContent(image) }
                else { ProgressView() }
                if asset.mediaType == .video {
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
            .onDisappear { if let requestID { manager.cancelImageRequest(requestID) } }
        }
    }

    @ViewBuilder
    private var canvasBackground: some View {
        if displayMode == .fit {
            Color.black
            if let image, !reduceTransparency {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.08)
                    .blur(radius: 28)
                    .opacity(0.58)
                Color.black.opacity(0.44)
            }
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
        "\(asset.localIdentifier)-\(displayMode)-\(Int(size.width))-\(Int(size.height))"
    }
    private func request(size: CGSize) {
        if let requestID { manager.cancelImageRequest(requestID) }
        let scale = UIScreen.main.scale
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let contentMode: PHImageContentMode = displayMode == .fit ? .aspectFit : .aspectFill
        requestID = manager.requestImage(for: asset, targetSize: CGSize(width: size.width * scale, height: size.height * scale), contentMode: contentMode, options: options) { result, _ in
            Task { @MainActor in image = result }
        }
    }
}
