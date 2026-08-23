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
    @State private var sharePayload: PhotoSharePayload?

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
            .sheet(item: $sharePayload) { payload in
                ActivityShareSheet(items: [payload.image])
            }
            .onDisappear {
                cancelSharePreparation()
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
                .padding(.bottom, 120)
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
            .accessibilityLabel("写真を共有")
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
    }

    private var isFavorite: Bool {
        favoriteOverride ?? asset.isFavorite
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
                guard let data, let image = UIImage(data: data) else { return }
                sharePayload = PhotoSharePayload(image: image)
            }
        }
    }

    private func cancelSharePreparation() {
        shareRequestGeneration &+= 1
        if let shareRequestID { manager.cancelImageRequest(shareRequestID) }
        shareRequestID = nil
        isPreparingShare = false
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
            .overlay(alignment: stampAlignment) { stamp }
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(Color.swipeeBorder, lineWidth: 1) }
            .shadow(color: .black.opacity(0.15), radius: 18, y: 9)
    }

    @ViewBuilder
    private var cardMedia: some View {
        if asset.mediaType == .video {
            VideoAssetView(
                asset: asset,
                manager: manager,
                allowsNetworkAccess: allowsNetworkAccess,
                playbackEnabled: isInteractive && !isDragging && !isExiting && !showingMetadata,
                showsControls: showsSideActions
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

    @ViewBuilder private var stamp: some View {
        let data: (String, Color)? = {
            if offset.width < -55 { return ("削除候補", .swipeeDelete) }
            if offset.width > 55 { return ("キープ", .swipeeKeep) }
            return nil
        }()
        if let data {
            Text(data.0).font(.title2).fontWeight(.black).foregroundStyle(data.1).padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.swipeePhotoOverlay, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(data.1, lineWidth: 4) }.rotationEffect(.degrees(-10)).padding(24)
        }
    }
    private var stampAlignment: Alignment { offset.width < 0 ? .topTrailing : .topLeading }
}
