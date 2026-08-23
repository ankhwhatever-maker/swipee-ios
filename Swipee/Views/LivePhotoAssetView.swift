import Photos
import PhotosUI
import SwiftUI

private enum LivePhotoPlaybackCommand: Hashable {
    case stop
    case hint
    case full
}

struct LivePhotoAssetView: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let allowsNetworkAccess: Bool

    @AppStorage("livePhotoPreviewEnabled") private var previewEnabled = true
    @State private var livePhoto: PHLivePhoto?
    @State private var requestID: PHImageRequestID?
    @State private var requestGeneration = 0
    @State private var viewSize: CGSize = .zero
    @State private var playbackCommand: LivePhotoPlaybackCommand = .stop
    @State private var playbackCommandID = 0
    @State private var pendingPlaybackCommand: LivePhotoPlaybackCommand?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                AssetImageView(
                    asset: asset,
                    manager: manager,
                    displayMode: .fit,
                    allowsNetworkAccess: allowsNetworkAccess
                )

                if let livePhoto {
                    LivePhotoPlayer(
                        livePhoto: livePhoto,
                        command: playbackCommand,
                        commandID: playbackCommandID
                    )
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }

                livePhotoBadge
                    .padding(12)
            }
            .background(.black)
            .clipped()
            .task(id: requestKey(size: proxy.size)) {
                viewSize = proxy.size
                if previewEnabled {
                    pendingPlaybackCommand = .hint
                    requestLivePhoto(size: proxy.size)
                }
            }
            .onChange(of: proxy.size) { _, size in
                viewSize = size
            }
            .onChange(of: previewEnabled) { _, isEnabled in
                if isEnabled {
                    if livePhoto != nil {
                        issuePlaybackCommand(.hint)
                    } else {
                        pendingPlaybackCommand = .hint
                        requestLivePhoto(size: viewSize)
                    }
                } else {
                    pendingPlaybackCommand = nil
                    issuePlaybackCommand(.stop)
                    cancelRequest()
                    livePhoto = nil
                }
            }
            .onDisappear {
                issuePlaybackCommand(.stop)
                cancelRequest()
            }
        }
    }

    private var livePhotoBadge: some View {
        Menu {
            Button("再生") {
                playFullLivePhoto()
            }
            Button(previewEnabled ? "プレビューを無効化" : "プレビューを有効化") {
                previewEnabled.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(
                    uiImage: PHLivePhotoView.livePhotoBadgeImage(
                        options: previewEnabled ? [.overContent] : [.overContent, .liveOff]
                    )
                )
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                Text("Live Photo")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(.black.opacity(0.48), in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.18), lineWidth: 1) }
            .contentShape(Rectangle().inset(by: -9))
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Live Photoの操作")
    }

    private func requestKey(size: CGSize) -> String {
        "\(asset.localIdentifier)-\(allowsNetworkAccess)-\(Int(size.width))-\(Int(size.height))"
    }

    private func playFullLivePhoto() {
        if livePhoto != nil {
            issuePlaybackCommand(.full)
        } else {
            pendingPlaybackCommand = .full
            requestLivePhoto(size: viewSize)
        }
    }

    private func requestLivePhoto(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        cancelRequest()
        requestGeneration &+= 1
        let generation = requestGeneration
        let requestedIdentifier = asset.localIdentifier
        let scale = UIScreen.main.scale
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = allowsNetworkAccess

        requestID = manager.requestLivePhoto(
            for: asset,
            targetSize: CGSize(width: size.width * scale, height: size.height * scale),
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            Task { @MainActor in
                guard generation == requestGeneration,
                      requestedIdentifier == asset.localIdentifier,
                      let result else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                guard livePhoto == nil || !isDegraded else { return }

                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    livePhoto = result
                }

                if !isDegraded, let command = pendingPlaybackCommand {
                    pendingPlaybackCommand = nil
                    issuePlaybackCommand(command)
                }
            }
        }
    }

    private func issuePlaybackCommand(_ command: LivePhotoPlaybackCommand) {
        playbackCommand = command
        playbackCommandID &+= 1
    }

    private func cancelRequest() {
        requestGeneration &+= 1
        if let requestID { manager.cancelImageRequest(requestID) }
        requestID = nil
    }
}

private struct LivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    let command: LivePhotoPlaybackCommand
    let commandID: Int

    final class Coordinator {
        var handledCommandID = -1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto !== livePhoto {
            view.livePhoto = livePhoto
        }
        guard context.coordinator.handledCommandID != commandID else { return }
        context.coordinator.handledCommandID = commandID

        switch command {
        case .stop:
            view.stopPlayback()
        case .hint:
            view.isMuted = true
            view.startPlayback(with: .hint)
        case .full:
            view.isMuted = false
            view.startPlayback(with: .full)
        }
    }

    static func dismantleUIView(_ view: PHLivePhotoView, coordinator: Coordinator) {
        view.stopPlayback()
        view.livePhoto = nil
    }
}
