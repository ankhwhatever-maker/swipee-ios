@preconcurrency import AVFoundation
import Photos
import SwiftUI
import UIKit

struct VideoAssetView: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let allowsNetworkAccess: Bool
    let playbackEnabled: Bool
    let player: AVPlayer
    @Binding var isMuted: Bool

    @State private var requestID: PHImageRequestID?
    @State private var requestGeneration = 0
    @State private var isLoading = true

    var body: some View {
        ZStack {
            AssetImageView(
                asset: asset,
                manager: manager,
                displayMode: .fit,
                allowsNetworkAccess: allowsNetworkAccess,
                showsVideoBadge: false
            )

            if player.currentItem != nil {
                VideoPlayerSurface(player: player)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if isLoading {
                ProgressView()
                    .tint(.white)
                    .padding(10)
                    .background(.black.opacity(0.38), in: Circle())
                    .allowsHitTesting(false)
            }

        }
        .background(.black)
        .clipped()
        .task(id: requestKey) {
            requestPlayerItem()
        }
        .onChange(of: playbackEnabled) { _, enabled in
            updatePlayback(isEnabled: enabled)
        }
        .onDisappear {
            cancelRequest()
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
    }

    private var requestKey: String {
        "\(asset.localIdentifier)-\(allowsNetworkAccess)"
    }

    private var duration: TimeInterval {
        max(asset.duration, 0)
    }

    private var elapsedTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? min(max(seconds, 0), duration) : 0
    }

    private var remainingTime: TimeInterval {
        max(duration - elapsedTime, 0)
    }

    private func requestPlayerItem() {
        cancelRequest()
        requestGeneration &+= 1
        let generation = requestGeneration
        let requestedIdentifier = asset.localIdentifier
        isLoading = true

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.version = .current
        options.isNetworkAccessAllowed = allowsNetworkAccess

        requestID = manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
            Task { @MainActor in
                guard generation == requestGeneration,
                      requestedIdentifier == asset.localIdentifier else { return }
                requestID = nil
                isLoading = false
                guard let item else { return }
                player.replaceCurrentItem(with: item)
                player.isMuted = isMuted
                if playbackEnabled {
                    player.play()
                }
            }
        }
    }

    private func updatePlayback(isEnabled: Bool) {
        guard player.currentItem != nil else { return }
        if isEnabled {
            if remainingTime < 0.1 {
                player.seek(to: .zero)
            }
            player.play()
        } else {
            player.pause()
        }
    }

    private func cancelRequest() {
        requestGeneration &+= 1
        if let requestID {
            manager.cancelImageRequest(requestID)
        }
        requestID = nil
        isLoading = false
    }
}

private struct VideoPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> VideoPlayerContainerView {
        let view = VideoPlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: VideoPlayerContainerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    static func dismantleUIView(_ view: VideoPlayerContainerView, coordinator: Void) {
        view.playerLayer.player = nil
    }
}

private final class VideoPlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
