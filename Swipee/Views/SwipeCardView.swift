@preconcurrency import AVFoundation
import Photos
import SwiftUI

struct SwipeCardView: View {
    let asset: PHAsset
    let manager: PHCachingImageManager
    let isInteractive: Bool
    let allowsNetworkAccess: Bool
    let maximumSize: CGSize
    let metadataBottomInset: CGFloat
    @Binding var requestedDecision: SwipeDecision?
    @Binding var activeSwipeDecision: SwipeDecision?
    let onToggleFavorite: (Bool) async -> Bool
    let onDecision: (SwipeDecision) async -> Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var metadataTouchActive = false
    @State private var offset: CGSize = .zero
    @State private var isExiting = false
    @State private var isDragging = false
    @State private var showingMetadata = false
    @State private var favoriteOverride: Bool?
    @State private var isUpdatingFavorite = false
    @State private var isPreparingShare = false
    @State private var shareRequestID: PHImageRequestID?
    @State private var shareRequestGeneration = 0
    @State private var sharePayload: AssetSharePayload?
    @State private var shareTemporaryDirectory: URL?
    @State private var shareErrorMessage: String?
    @State private var videoPlayer = AVPlayer()
    @State private var isVideoMuted = true

    var body: some View {
        interactiveArea
            .frame(width: maximumSize.width, height: maximumSize.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("写真カード")
            .accessibilityHint("左で削除候補、右でキープ")
            .accessibilityAction(named: "削除候補へ") { exit(.trash) }
            .accessibilityAction(named: "キープ") { exit(.keep) }
            .onChange(of: requestedDecision) { _, decision in if let decision { exit(decision) } }
            .onChange(of: metadataTouchActive) { wasActive, isActive in
                if wasActive, !isActive, showingMetadata {
                    withAnimation(.easeOut(duration: 0.14)) {
                        showingMetadata = false
                    }
                }
            }
            .sheet(item: $sharePayload, onDismiss: cleanupShareFiles) { payload in
                ActivityShareSheet(items: payload.items)
            }
            .alert("共有できません", isPresented: Binding(
                get: { shareErrorMessage != nil },
                set: { if !$0 { shareErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareErrorMessage ?? "")
            }
            .onDisappear {
                cancelSharePreparation()
                cleanupShareFiles()
            }
    }

    private var fittedCardSize: CGSize {
        guard asset.pixelWidth > 0, asset.pixelHeight > 0,
              maximumSize.width > 0, maximumSize.height > 0 else {
            return maximumSize
        }

        let imageAspectRatio = CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        let availableAspectRatio = maximumSize.width / maximumSize.height
        if imageAspectRatio > availableAspectRatio {
            return CGSize(
                width: maximumSize.width,
                height: maximumSize.width / imageAspectRatio
            )
        }
        return CGSize(
            width: maximumSize.height * imageAspectRatio,
            height: maximumSize.height
        )
    }

    private var interactiveArea: some View {
        ZStack {
            swipeRevealBackground
            movingCard

            if showingMetadata {
                PhotoMetadataPanel(asset: asset)
                    .padding(.bottom, metadataBottomInset)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if showsSideActions {
                        sideActions
                            .transition(.opacity)
                    }
                }
                .padding(.trailing, 4)
                .padding(.bottom, 160)
            }

            if asset.mediaType == .video, showsSideActions {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    videoTransportControls(refreshDate: context.date)
                }
                .transition(.opacity)
            }
        }
            .contentShape(Rectangle())
            .gesture(dragGesture, including: isInteractive ? .all : .none)
            .simultaneousGesture(longPressGesture, including: isInteractive ? .all : .none)
            .simultaneousGesture(metadataTouchGesture, including: isInteractive ? .all : .none)
            .allowsHitTesting(isInteractive && !isExiting)
    }

    private var showsSideActions: Bool {
        !showingMetadata && !isDragging && !isExiting
    }

    private var sideActions: some View {
        VStack(spacing: 4) {
            Button { toggleFavorite() } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .disabled(isUpdatingFavorite)
            .accessibilityLabel(isFavorite ? "お気に入りから外す" : "お気に入りに追加")

            Button { prepareShare() } label: {
                ZStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 19, weight: .semibold))
                    if isPreparingShare {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                            .offset(y: 22)
                    }
                }
                .frame(width: 44, height: 46)
            }
            .disabled(isPreparingShare)
            .accessibilityLabel("共有")

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 26, height: 1)
                .padding(.vertical, 7)
                .accessibilityHidden(true)

            Button { } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("詳細と編集")
            .accessibilityHint("準備中")
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
    }

    private var isFavorite: Bool {
        favoriteOverride ?? asset.isFavorite
    }

    private var videoPlaybackButton: some View {
        Button { toggleVideoPlayback() } label: {
            Image(systemName: videoPlayer.timeControlStatus == .playing ? "pause.fill" : "play.fill")
                .font(.system(size: 21, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
        .accessibilityLabel(videoPlayer.timeControlStatus == .playing ? "一時停止" : "再生")
    }

    private var videoMuteButton: some View {
        Button { toggleVideoMute() } label: {
            Image(systemName: isVideoMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 19, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
        .accessibilityLabel(isVideoMuted ? "音声をオン" : "ミュート")
    }

    private func videoTransportControls(refreshDate: Date) -> some View {
        let elapsed = videoElapsedTime

        return VStack(spacing: 6) {
            Spacer()

            HStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    videoPlaybackButton
                    Text(formattedVideoTime(elapsed))
                }
                Spacer()
                VStack(spacing: 0) {
                    videoMuteButton
                    Text("−\(formattedVideoTime(max(videoDuration - elapsed, 0)))")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 4)

            videoSeekBar(refreshDate: refreshDate)
        }
        .padding(.bottom, 10)
    }

    private func videoSeekBar(refreshDate: Date) -> some View {
        let progress = videoPlaybackProgress

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.22))
                Rectangle()
                    .fill(.white)
                    .frame(width: proxy.size.width * progress)
                    .id(refreshDate.timeIntervalSinceReferenceDate)
            }
            .contentShape(Rectangle().inset(by: -10))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        seekVideo(to: value.location.x, width: proxy.size.width)
                    }
            )
        }
        .frame(width: max(maximumSize.width - 4, 0), height: 4)
        .accessibilityLabel("再生位置")
        .accessibilityValue("\(Int(progress * 100))パーセント")
        .accessibilityAdjustableAction { direction in
            let adjustment: TimeInterval = direction == .increment ? 5 : -5
            seekVideo(to: videoElapsedTime + adjustment)
        }
    }

    private var videoDuration: TimeInterval {
        max(asset.duration, 0)
    }

    private var videoElapsedTime: TimeInterval {
        let seconds = videoPlayer.currentTime().seconds
        return seconds.isFinite ? min(max(seconds, 0), videoDuration) : 0
    }

    private var videoPlaybackProgress: CGFloat {
        guard videoDuration > 0 else { return 0 }
        return CGFloat(min(max(videoElapsedTime / videoDuration, 0), 1))
    }

    private func formattedVideoTime(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval.rounded(.down)), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func seekVideo(to horizontalPosition: CGFloat, width: CGFloat) {
        guard width > 0, videoDuration > 0 else { return }
        let progress = min(max(horizontalPosition / width, 0), 1)
        seekVideo(to: videoDuration * progress)
    }

    private func seekVideo(to seconds: TimeInterval) {
        guard videoDuration > 0 else { return }
        let destination = min(max(seconds, 0), videoDuration)
        videoPlayer.seek(
            to: CMTime(seconds: destination, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600)
        )
    }

    private func toggleVideoPlayback() {
        if videoPlayer.timeControlStatus == .playing {
            videoPlayer.pause()
        } else {
            let duration = max(asset.duration, 0)
            let elapsed = videoPlayer.currentTime().seconds
            if elapsed.isFinite, duration - elapsed < 0.1 {
                videoPlayer.seek(to: .zero)
            }
            videoPlayer.play()
        }
    }

    private func toggleVideoMute() {
        isVideoMuted.toggle()
        videoPlayer.isMuted = isVideoMuted
    }

    private func toggleFavorite() {
        guard !isUpdatingFavorite, !isExiting else { return }
        let nextValue = !isFavorite
        favoriteOverride = nextValue
        isUpdatingFavorite = true
        Task {
            let didComplete = await onToggleFavorite(nextValue)
            if !didComplete { favoriteOverride = !nextValue }
            isUpdatingFavorite = false
        }
    }

    private func prepareShare() {
        guard !isPreparingShare, !isExiting else { return }
        isPreparingShare = true
        shareRequestGeneration &+= 1
        let generation = shareRequestGeneration

        if asset.mediaType == .video {
            prepareResourceShare(
                resources: preferredVideoResources(),
                generation: generation,
                unavailableMessage: "動画を取得できませんでした。iCloudまたは写真へのアクセスを確認してください。"
            )
        } else if asset.mediaSubtypes.contains(.photoLive) {
            prepareResourceShare(
                resources: preferredLivePhotoResources(),
                generation: generation,
                unavailableMessage: "Live Photoを取得できませんでした。iCloudまたは写真へのアクセスを確認してください。"
            )
        } else {
            preparePhotoShare(generation: generation)
        }
    }

    private func preparePhotoShare(generation: Int) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .current
        options.isNetworkAccessAllowed = true
        shareRequestID = manager.requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            Task { @MainActor in
                guard generation == shareRequestGeneration else { return }
                isPreparingShare = false
                shareRequestID = nil
                guard let data, let image = UIImage(data: data) else {
                    shareErrorMessage = "写真を取得できませんでした。iCloudまたは写真へのアクセスを確認してください。"
                    return
                }
                sharePayload = AssetSharePayload(items: [image])
            }
        }
    }

    private func prepareResourceShare(
        resources: [PHAssetResource],
        generation: Int,
        unavailableMessage: String
    ) {
        guard !resources.isEmpty else {
            isPreparingShare = false
            shareErrorMessage = unavailableMessage
            return
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwipeeShare-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            isPreparingShare = false
            shareErrorMessage = "共有ファイルを準備できませんでした。"
            return
        }

        let destinations = resources.enumerated().map { index, resource in
            let originalName = URL(fileURLWithPath: resource.originalFilename).lastPathComponent
            let fallbackName = "media-\(index + 1)"
            let filename = originalName.isEmpty ? fallbackName : originalName
            return directory.appendingPathComponent(filename)
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        Self.writeShareResources(
            resources,
            to: destinations,
            options: options
        ) { error in
            Task { @MainActor in
                guard generation == shareRequestGeneration else {
                    try? FileManager.default.removeItem(at: directory)
                    return
                }
                isPreparingShare = false
                guard error == nil else {
                    try? FileManager.default.removeItem(at: directory)
                    shareErrorMessage = unavailableMessage
                    return
                }
                cleanupShareFiles()
                shareTemporaryDirectory = directory
                sharePayload = AssetSharePayload(items: destinations)
            }
        }
    }

    private func preferredVideoResources() -> [PHAssetResource] {
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first(where: { $0.type == .fullSizeVideo })
            ?? resources.first(where: { $0.type == .video }) {
            return [resource]
        }
        return []
    }

    private func preferredLivePhotoResources() -> [PHAssetResource] {
        let resources = PHAssetResource.assetResources(for: asset)
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

    private static func writeShareResources(
        _ resources: [PHAssetResource],
        to destinations: [URL],
        options: PHAssetResourceRequestOptions,
        index: Int = 0,
        completion: @escaping (Error?) -> Void
    ) {
        guard index < resources.count else {
            completion(nil)
            return
        }
        PHAssetResourceManager.default().writeData(
            for: resources[index],
            toFile: destinations[index],
            options: options
        ) { error in
            if let error {
                completion(error)
            } else {
                writeShareResources(
                    resources,
                    to: destinations,
                    options: options,
                    index: index + 1,
                    completion: completion
                )
            }
        }
    }

    private func cancelSharePreparation() {
        shareRequestGeneration &+= 1
        if let shareRequestID { manager.cancelImageRequest(shareRequestID) }
        shareRequestID = nil
        isPreparingShare = false
    }

    private func cleanupShareFiles() {
        guard let shareTemporaryDirectory else { return }
        try? FileManager.default.removeItem(at: shareTemporaryDirectory)
        self.shareTemporaryDirectory = nil
    }

    private var movingCard: some View {
        styledCard
            .frame(width: fittedCardSize.width, height: fittedCardSize.height)
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 24)))
    }

    private var styledCard: some View {
        cardMedia
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(Color.swipeeBorder, lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 18, y: 9)
    }

    @ViewBuilder
    private var swipeRevealBackground: some View {
        if let presentation = swipeRevealPresentation {
            HStack {
                if presentation.decision == .trash { Spacer() }
                VStack(spacing: 12) {
                    Image(systemName: presentation.icon)
                        .font(.system(size: 54, weight: .bold))
                    Text(presentation.title)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                }
                .foregroundStyle(presentation.foregroundColor)
                .scaleEffect(0.84 + swipeRevealProgress * 0.16)
                .opacity(swipeRevealProgress)
                .padding(.horizontal, 34)
                if presentation.decision == .keep { Spacer() }
            }
            .allowsHitTesting(false)
        }
    }

    private var swipeRevealProgress: CGFloat {
        min(max((abs(offset.width) - 6) / 120, 0), 1)
    }

    private var swipeRevealPresentation: SwipeRevealPresentation? {
        let decision: SwipeDecision?
        if offset.width < -6 {
            decision = .trash
        } else if offset.width > 6 {
            decision = .keep
        } else {
            decision = activeSwipeDecision
        }

        switch decision {
        case .trash:
            return SwipeRevealPresentation(
                decision: .trash,
                title: "削除",
                icon: "trash.fill",
                foregroundColor: Color(red: 0.70, green: 0.49, blue: 0.96)
            )
        case .keep:
            return SwipeRevealPresentation(
                decision: .keep,
                title: "キープ",
                icon: "hand.thumbsup.fill",
                foregroundColor: Color(red: 0.43, green: 0.94, blue: 0.66)
            )
        default:
            return nil
        }
    }

    @ViewBuilder
    private var cardMedia: some View {
        if asset.mediaType == .video {
            VideoAssetView(
                asset: asset,
                manager: manager,
                allowsNetworkAccess: allowsNetworkAccess,
                playbackEnabled: isInteractive && !isDragging && !isExiting && !showingMetadata,
                player: videoPlayer,
                isMuted: $isVideoMuted
            )
        } else if asset.mediaSubtypes.contains(.photoLive) {
            LivePhotoAssetView(
                asset: asset,
                manager: manager,
                allowsNetworkAccess: allowsNetworkAccess
            )
        } else {
            AssetImageView(
                asset: asset,
                manager: manager,
                displayMode: .fit,
                allowsNetworkAccess: allowsNetworkAccess
            )
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    withAnimation(.easeOut(duration: 0.12)) {
                        isDragging = true
                    }
                    cancelSharePreparation()
                }
                if showingMetadata {
                    withAnimation(.easeOut(duration: 0.1)) {
                        showingMetadata = false
                    }
                }
                offset = value.translation
                updateActiveSwipeDecision(for: value.translation)
            }
            .onEnded { value in
                if let decision = decision(for: value) { exit(decision) }
                else {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72)) {
                        offset = .zero
                        activeSwipeDecision = nil
                        isDragging = false
                    }
                }
            }
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 12)
            .onEnded { _ in showMetadata() }
    }

    private var metadataTouchGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($metadataTouchActive) { _, state, _ in
                state = true
            }
    }

    private func showMetadata() {
        guard isInteractive, !isExiting, !showingMetadata else { return }
        activeSwipeDecision = nil
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        withAnimation(.easeInOut(duration: 0.22)) {
            showingMetadata = true
        }
    }

    private func decision(for value: DragGesture.Value) -> SwipeDecision? {
        let predicted = value.predictedEndTranslation
        guard abs(predicted.width) > abs(predicted.height) else { return nil }
        if predicted.width < -110 { return .trash }
        if predicted.width > 110 { return .keep }
        return nil
    }

    private func updateActiveSwipeDecision(for translation: CGSize) {
        let nextDecision: SwipeDecision?
        if abs(translation.width) <= abs(translation.height) {
            nextDecision = nil
        } else if translation.width < -36 {
            nextDecision = .trash
        } else if translation.width > 36 {
            nextDecision = .keep
        } else {
            nextDecision = nil
        }

        guard nextDecision != activeSwipeDecision else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.74)) {
            activeSwipeDecision = nextDecision
        }
    }

    private func exit(_ decision: SwipeDecision) {
        guard isInteractive, !isExiting else { return }
        showingMetadata = false
        isExiting = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72)) {
            activeSwipeDecision = decision
        }
        let destination: CGSize = switch decision {
        case .trash: CGSize(width: -700, height: offset.height * 0.25)
        case .keep: CGSize(width: 700, height: offset.height * 0.25)
        case .favorite: CGSize(width: offset.width * 0.2, height: -900)
        }
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) { offset = destination }
        Task {
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(250)) }
            requestedDecision = nil
            let didComplete = await onDecision(decision)
            activeSwipeDecision = nil
            guard !didComplete else { return }

            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72)) {
                offset = .zero
                isDragging = false
            }
            isExiting = false
        }
    }

}

private struct SwipeRevealPresentation {
    let decision: SwipeDecision
    let title: String
    let icon: String
    let foregroundColor: Color
}
