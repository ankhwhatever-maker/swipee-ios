import Photos
import SwiftUI

struct PhotoDetailView: View {
    let asset: PHAsset
    let manager: PHCachingImageManager

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var gestureScale: CGFloat = 1
    @GestureState private var gestureOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale * gestureScale)
                        .offset(
                            x: offset.width + gestureOffset.width,
                            y: offset.height + gestureOffset.height
                        )
                        .gesture(zoomGesture.simultaneously(with: panGesture))
                        .onTapGesture(count: 2) { toggleZoom() }
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .task(id: requestKey(size: proxy.size)) { requestImage(size: proxy.size) }
            .onDisappear {
                if let requestID { manager.cancelImageRequest(requestID) }
            }
            .overlay(alignment: .topTrailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .accessibilityLabel("閉じる")
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                scale = min(max(scale * value, 1), 5)
                if scale == 1 { offset = .zero }
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($gestureOffset) { value, state, _ in
                guard scale * gestureScale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard scale > 1 else {
                    offset = .zero
                    return
                }
                offset.width += value.translation.width
                offset.height += value.translation.height
            }
    }

    private func toggleZoom() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            if scale > 1 {
                scale = 1
                offset = .zero
            } else {
                scale = 2
            }
        }
    }

    private func requestKey(size: CGSize) -> String {
        "\(asset.localIdentifier)-detail-\(Int(size.width))-\(Int(size.height))"
    }

    private func requestImage(size: CGSize) {
        if let requestID { manager.cancelImageRequest(requestID) }
        let displayScale = UIScreen.main.scale
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        requestID = manager.requestImage(
            for: asset,
            targetSize: CGSize(width: size.width * displayScale, height: size.height * displayScale),
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            Task { @MainActor in image = result }
        }
    }
}
