import Photos
import SwiftUI
import UIKit

struct DuplicateGroupSwipeView: View {
    @EnvironmentObject private var duplicateSessions: DuplicateSessionStore
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var analysis: DuplicateAnalysisService
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let group: DuplicatePhotoGroup

    @State private var assets: [PHAsset] = []
    @State private var processing = false
    @State private var requestedDecision: SwipeDecision?
    @State private var activeSwipeDecision: SwipeDecision?
    @State private var showingReview = false
    @State private var reviewFinished = false
    @State private var reviewingAssetIdentifiers: [String] = []
    @State private var reviewingFinalBatch = false
    @State private var restoringCard: RestoringCard?
    @State private var restorationProgress: CGFloat = 0
    @State private var cachedAssets: [PHAsset] = []
    private let actionOverlayHeight: CGFloat = 76
    private let thumbnailStripHeight: CGFloat = 82
    private let batchSize = 10

    private struct RestoringCard {
        let asset: PHAsset
        let decision: SwipeDecision
    }

    private var items: [ReviewSessionItem] {
        duplicateSessions.items(for: group.id)
    }

    private var remainingAssets: [PHAsset] {
        let reviewedIdentifiers = Set(items.map(\.assetIdentifier))
        return assets.filter { !reviewedIdentifiers.contains($0.localIdentifier) }
    }

    private var currentBatchItems: [ReviewSessionItem] {
        let completedCount = duplicateSessions.completedCount(for: group.id)
        return Array(items.dropFirst(completedCount).prefix(batchSize))
    }

    private var shouldReviewCurrentBatch: Bool {
        !currentBatchItems.isEmpty
            && (currentBatchItems.count >= batchSize || remainingAssets.isEmpty)
    }

    private var deckBackground: LinearGradient {
        let colors: [Color]
        let startPoint: UnitPoint
        let endPoint: UnitPoint

        switch activeSwipeDecision {
        case .trash:
            colors = [
                Color(red: 0.08, green: 0.05, blue: 0.12),
                Color(red: 0.24, green: 0.15, blue: 0.34)
            ]
            startPoint = .topTrailing
            endPoint = .bottomLeading
        case .keep:
            colors = [
                Color(red: 0.02, green: 0.10, blue: 0.06),
                Color(red: 0.10, green: 0.31, blue: 0.20)
            ]
            startPoint = .topLeading
            endPoint = .bottomTrailing
        default:
            let restingColor = Color(red: 0.043, green: 0.043, blue: 0.051)
            colors = [restingColor, restingColor]
            startPoint = .topLeading
            endPoint = .bottomTrailing
        }

        return LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
    }

    var body: some View {
        ZStack {
            Group {
                if shouldReviewCurrentBatch {
                    Color.swipeeBackground
                } else {
                    deckBackground
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: activeSwipeDecision)
                }
            }
            .ignoresSafeArea()
            Group {
                if assets.isEmpty {
                    ProgressView().tint(.white)
                } else if shouldReviewCurrentBatch {
                    readyState
                } else {
                    deck
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .task {
            assets = library.fetchAssets(localIdentifiers: group.assetIdentifiers)
            updateImageCache()
            if shouldReviewCurrentBatch { prepareReview() }
        }
        .onDisappear { stopImageCache() }
        .fullScreenCover(isPresented: $showingReview, onDismiss: {
            guard reviewFinished else { return }
            reviewFinished = false
            if reviewingFinalBatch {
                dismiss()
                Task {
                    await analysis.analyzeIfNeeded(
                        library: library,
                        pendingDeletions: pendingDeletions
                    )
                }
            } else {
                reviewingAssetIdentifiers = []
                reviewingFinalBatch = false
                updateImageCache()
            }
        }) {
            DuplicateGroupReviewView(
                group: group,
                batchAssetIdentifiers: reviewingAssetIdentifiers,
                isFinalBatch: reviewingFinalBatch
            ) {
                reviewFinished = true
                showingReview = false
            }
        }
        .alert("操作を完了できませんでした", isPresented: Binding(
            get: { library.errorMessage != nil },
            set: { if !$0 { library.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var deck: some View {
        VStack(spacing: 0) {
            deckHeader

            GeometryReader { proxy in
                ZStack {
                    if let asset = remainingAssets.first {
                        let restoration = restoringCard?.asset.localIdentifier == asset.localIdentifier
                            ? restoringCard
                            : nil
                        SwipeCardView(
                            asset: asset,
                            manager: library.imageManager,
                            isInteractive: !processing && restoration == nil,
                            allowsNetworkAccess: true,
                            maximumSize: proxy.size,
                            metadataBottomInset: 0,
                            requestedDecision: $requestedDecision,
                            activeSwipeDecision: $activeSwipeDecision
                        ) { isFavorite in
                            await setFavorite(asset, isFavorite: isFavorite)
                        } onDecision: {
                            await decide($0, asset: asset)
                        }
                        .id(asset.localIdentifier)
                        .offset(restoration.map { restorationOffset(for: $0.decision, in: proxy.size) } ?? .zero)
                        .rotationEffect(restoration.map { restorationRotation(for: $0.decision) } ?? .zero)
                        .opacity(restoration != nil && reduceMotion ? restorationProgress : 1)
                        .accessibilityHidden(restoration != nil)
                        .transition(.opacity)
                    }
                }
            }

            actionControls
                .frame(height: actionOverlayHeight)

            thumbnailStrip
                .frame(height: thumbnailStripHeight)
        }
    }

    private var deckHeader: some View {
        ZStack {
            progressPill
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(.white)
                .accessibilityLabel("重複候補へ戻る")
                Spacer()
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 4)
    }

    private var comparisonAssets: [PHAsset] {
        guard let currentIdentifier = remainingAssets.first?.localIdentifier else { return [] }
        return Array(
            remainingAssets.lazy
                .filter { $0.localIdentifier != currentIdentifier }
                .prefix(10)
        )
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(comparisonAssets, id: \.localIdentifier) { asset in
                    AssetImageView(
                        asset: asset,
                        manager: library.imageManager,
                        displayMode: .fill,
                        allowsNetworkAccess: false
                    )
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    }
                    .accessibilityLabel("同じグループの写真")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)
        }
        .accessibilityLabel("同じグループの写真、最大10枚")
    }

    private var actionControls: some View {
        ZStack {
            HStack(spacing: 32) {
                actionButton("削除", color: .swipeeDelete, decision: .trash) {
                    requestedDecision = .trash
                }
                actionButton("キープ", color: .swipeeKeep, decision: .keep) {
                    requestedDecision = .keep
                }
            }
            HStack {
                undoButton
                    .opacity(activeSwipeDecision == nil ? 1 : 0)
                    .scaleEffect(activeSwipeDecision == nil ? 1 : 0.72)
                Spacer()
            }
        }
    }

    private var readyState: some View {
        ReviewBatchReadyScreen(itemCount: currentBatchItems.count) {
            prepareReview()
        }
    }

    private var progressPill: some View {
        Text("\(min(currentBatchItems.count + 1, batchTargetCount)) / \(batchTargetCount)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.swipeePhotoOverlay, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.22)) }
            .accessibilityLabel("今回の重複整理、\(batchTargetCount)枚中\(min(currentBatchItems.count + 1, batchTargetCount))枚目")
    }

    private var batchTargetCount: Int {
        min(batchSize, currentBatchItems.count + remainingAssets.count)
    }

    private var undoButton: some View {
        Button { undoLastAction() } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.subheadline.bold())
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.12), in: Circle())
                .overlay { Circle().stroke(.white.opacity(0.2)) }
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(.white.opacity(0.82))
        .opacity(canUndo ? 1 : 0.28)
        .disabled(processing || !canUndo)
        .accessibilityLabel("直前の操作を戻す")
    }

    private func actionButton(
        _ title: String,
        color: Color,
        decision: SwipeDecision,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.bold())
                .frame(width: 86, height: 54)
                .background(.white.opacity(0.12), in: Capsule())
                .overlay { Capsule().stroke(.white.opacity(0.2)) }
                .foregroundStyle(color)
        }
        .scaleEffect(activeSwipeDecision == decision ? 1.28 : 1)
        .opacity(activeSwipeDecision == nil || activeSwipeDecision == decision ? 1 : 0)
        .disabled(processing)
        .accessibilityLabel(title)
    }

    private func decide(_ decision: SwipeDecision, asset: PHAsset) async -> Bool {
        guard !processing, remainingAssets.first?.localIdentifier == asset.localIdentifier else { return false }
        processing = true
        do {
            let previousFavoriteState = decision == .favorite ? asset.isFavorite : nil
            if decision == .favorite { try await library.markFavorite(asset) }
            if decision == .trash {
                pendingDeletions.enqueue(
                    assetIdentifier: asset.localIdentifier,
                    sourceConditionKey: "duplicates|\(group.id)"
                )
            }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.12)) {
                duplicateSessions.append(
                    groupIdentifier: group.id,
                    assetIdentifier: asset.localIdentifier,
                    decision: decision,
                    previousFavoriteState: previousFavoriteState
                )
            }
            updateImageCache()
            processing = false
            if shouldReviewCurrentBatch { prepareReview() }
            return true
        } catch {
            library.errorMessage = error.localizedDescription
            processing = false
            return false
        }
    }

    private func setFavorite(_ asset: PHAsset, isFavorite: Bool) async -> Bool {
        do {
            try await library.setFavorite(asset, isFavorite: isFavorite)
            return true
        } catch {
            library.errorMessage = error.localizedDescription
            return false
        }
    }

    private var canUndo: Bool {
        guard let action = currentBatchItems.last else { return false }
        if action.decision == .trash {
            return pendingDeletions.contains(assetIdentifier: action.assetIdentifier)
        }
        return true
    }

    private func undoLastAction() {
        guard !processing, let action = currentBatchItems.last else { return }
        processing = true
        Task {
            let originalDecision = action.originalDecision ?? action.decision
            guard let asset = library.fetchAssets(localIdentifiers: [action.assetIdentifier]).first else {
                if action.decision == .trash {
                    pendingDeletions.remove(assetIdentifier: action.assetIdentifier)
                }
                duplicateSessions.removeLast(groupIdentifier: group.id)
                updateImageCache()
                processing = false
                return
            }

            do {
                if originalDecision == .favorite {
                    try await library.setFavorite(asset, isFavorite: action.previousFavoriteState ?? false)
                }
                if action.decision == .trash {
                    pendingDeletions.remove(assetIdentifier: action.assetIdentifier)
                }
                duplicateSessions.removeLast(groupIdentifier: group.id)
                updateImageCache()
                await restore(asset, from: originalDecision)
            } catch {
                library.errorMessage = error.localizedDescription
            }
            processing = false
        }
    }

    private func prepareReview() {
        guard !showingReview, !currentBatchItems.isEmpty else { return }
        reviewingAssetIdentifiers = currentBatchItems.map(\.assetIdentifier)
        reviewingFinalBatch = remainingAssets.isEmpty
        showingReview = true
    }

    private func restore(_ asset: PHAsset, from decision: SwipeDecision) async {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        restoringCard = RestoringCard(asset: asset, decision: decision)
        restorationProgress = 0
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(16))
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) { restorationProgress = 1 }
            try? await Task.sleep(for: .milliseconds(180))
        } else {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                restorationProgress = 1
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        feedback.impactOccurred()
        restoringCard = nil
        restorationProgress = 0
    }

    private func restorationOffset(for decision: SwipeDecision, in size: CGSize) -> CGSize {
        guard !reduceMotion else { return .zero }
        let remaining = 1 - restorationProgress
        switch decision {
        case .trash: return CGSize(width: -max(size.width * 1.15, 420) * remaining, height: 18 * remaining)
        case .keep: return CGSize(width: max(size.width * 1.15, 420) * remaining, height: 18 * remaining)
        case .favorite: return CGSize(width: 0, height: -max(size.height * 1.15, 620) * remaining)
        }
    }

    private func restorationRotation(for decision: SwipeDecision) -> Angle {
        guard !reduceMotion else { return .zero }
        let remaining = 1 - restorationProgress
        switch decision {
        case .trash: return .degrees(-10 * remaining)
        case .keep: return .degrees(10 * remaining)
        case .favorite: return .zero
        }
    }

    private func updateImageCache() {
        let nextAssets = Array(remainingAssets.prefix(3))
        let nextIdentifiers = Set(nextAssets.map(\.localIdentifier))
        let currentIdentifiers = Set(cachedAssets.map(\.localIdentifier))
        let removedAssets = cachedAssets.filter { !nextIdentifiers.contains($0.localIdentifier) }
        let addedAssets = nextAssets.filter { !currentIdentifiers.contains($0.localIdentifier) }
        let options = cacheRequestOptions

        if !removedAssets.isEmpty {
            library.imageManager.stopCachingImages(
                for: removedAssets,
                targetSize: cacheTargetSize,
                contentMode: .aspectFit,
                options: options
            )
        }
        if !addedAssets.isEmpty {
            library.imageManager.startCachingImages(
                for: addedAssets,
                targetSize: cacheTargetSize,
                contentMode: .aspectFit,
                options: options
            )
        }
        cachedAssets = nextAssets
    }

    private func stopImageCache() {
        guard !cachedAssets.isEmpty else { return }
        library.imageManager.stopCachingImages(
            for: cachedAssets,
            targetSize: cacheTargetSize,
            contentMode: .aspectFit,
            options: cacheRequestOptions
        )
        cachedAssets = []
    }

    private var cacheTargetSize: CGSize {
        CGSize(width: 900, height: 1200)
    }

    private var cacheRequestOptions: PHImageRequestOptions {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        return options
    }
}
