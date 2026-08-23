@preconcurrency import AVFoundation
import Photos
import SwiftUI
import UIKit

struct VideoAssetView: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let allowsNetworkAccess: Bool
    let playbackEnabled: Bool
    let showsControls: Bool

    @State private var player = AVPlayer()
    @State private var requestID: PHImageRequestID?
    @State private var requestGeneration = 0
    @State private var isLoading = true
    @State private var isMuted = true

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

            if showsControls {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    controls
                }
                .transition(.opacity)
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

    private var controls: some View {
        VStack(spacing: 8) {
            Spacer()

            HStack {
                controlButton(
                    player.timeControlStatus == .playing ? "pause.fill" : "play.fill",
                    label: player.timeControlStatus == .playing ? "一時停止" : "再生",
                    action: togglePlayback
                )
                Spacer()
                controlButton(
                    isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    label: isMuted ? "音声をオン" : "ミュート",
                    action: toggleMute
                )
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * playbackProgress)
                }
            }
            .frame(height: 4)
            .allowsHitTesting(false)

            HStack {
                Text(formattedTime(elapsedTime))
                Spacer()
                Text("−\(formattedTime(remainingTime))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.72))
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 80)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func controlButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
        .accessibilityLabel(label)
    }

    private var requestKey: String {
        "\(asset.localIdentifier)-\(allowsNetworkAccess)"
    }

    private var elapsedTime: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? min(max(seconds, 0), duration) : 0
    }

    private var duration: TimeInterval {
        max(asset.duration, 0)
    }

    private var remainingTime: TimeInterval {
        max(duration - elapsedTime, 0)
    }

    private var playbackProgress: CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(max(elapsedTime / duration, 0), 1))
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded(.down)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
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

    private func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            if remainingTime < 0.1 {
                player.seek(to: .zero)
            }
            player.play()
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        player.isMuted = isMuted
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
