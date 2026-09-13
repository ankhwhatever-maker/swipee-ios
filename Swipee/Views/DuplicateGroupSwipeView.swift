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

    let group: DuplicatePhotoGroup

    @State private var assets: [PHAsset] = []
    @State private var hasLoadedAssets = false
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

    var body: some View {
        ZStack {
            SwipeDeckBackground(
                activeDecision: activeSwipeDecision,
                isDeckVisible: !shouldReviewCurrentBatch && !(hasLoadedAssets && assets.isEmpty),
                reduceMotion: reduceMotion
            )
                .ignoresSafeArea()
            Group {
                if !hasLoadedAssets {
                    ProgressView().tint(.white)
                } else if assets.isEmpty {
                    unavailableState
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
            hasLoadedAssets = true
            updateImageCache()
            if shouldReviewCurrentBatch { prepareReview() }
        }
        .onDisappear { stopImageCache() }
        .fullScreenCover(isPresented: $showingReview, onDismiss: {
            guard reviewFinished else { return }
            reviewFinished = false
            reviewingAssetIdentifiers = []
            reviewingFinalBatch = false
            updateImageCache()
        }) {
            DuplicateGroupReviewView(
                group: group,
                batchAssetIdentifiers: reviewingAssetIdentifiers,
                isFinalBatch: reviewingFinalBatch,
                onPrimaryAction: finishReviewFromPrimaryAction
            )
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
                        .cardRestorationEffect(
                            decision: restoration?.decision,
                            progress: restorationProgress,
                            availableSize: proxy.size,
                            reduceMotion: reduceMotion
                        )
                        .transition(.opacity)
                    }
                }
            }

            SwipeActionControls(
                activeDecision: activeSwipeDecision,
                isProcessing: processing,
                canUndo: canUndo,
                onDelete: { requestedDecision = .trash },
                onKeep: { requestedDecision = .keep },
                onUndo: undoLastAction
            )
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

    private var readyState: some View {
        ReviewBatchReadyScreen(
            itemCount: currentBatchItems.count,
            onBack: { dismiss() },
            onReview: prepareReview
        )
    }

    private var unavailableState: some View {
        ContentUnavailableView {
            Label("このグループの写真を表示できません", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("写真が削除されたか、現在の写真アクセス範囲から外れている可能性があります。")
        } actions: {
            Button("重複候補へ戻る") { dismiss() }
                .buttonStyle(.borderedProminent)
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

    private func decide(_ decision: SwipeDecision, asset: PHAsset) async -> Bool {
        guard !processing, remainingAssets.first?.localIdentifier == asset.localIdentifier else { return false }
        processing = true
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
                decision: decision
            )
        }
        updateImageCache()
        processing = false
        if shouldReviewCurrentBatch { prepareReview() }
        return true
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
            guard let asset = library.fetchAssets(localIdentifiers: [action.assetIdentifier]).first else {
                if action.decision == .trash {
                    pendingDeletions.remove(assetIdentifier: action.assetIdentifier)
                }
                duplicateSessions.removeLast(groupIdentifier: group.id)
                updateImageCache()
                processing = false
                return
            }

            if action.decision == .trash {
                pendingDeletions.remove(assetIdentifier: action.assetIdentifier)
            }
            duplicateSessions.removeLast(groupIdentifier: group.id)
            updateImageCache()
            await restore(asset, from: action.decision)
            processing = false
        }
    }

    private func prepareReview() {
        guard !showingReview, !currentBatchItems.isEmpty else { return }
        reviewingAssetIdentifiers = currentBatchItems.map(\.assetIdentifier)
        reviewingFinalBatch = remainingAssets.isEmpty
        showingReview = true
    }

    private func finishReviewFromPrimaryAction() {
        if reviewingFinalBatch {
            finishReviewAndReturnToList()
        } else {
            reviewFinished = true
            showingReview = false
        }
    }

    private func finishReviewAndReturnToList() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dismiss()
        }
        Task {
            await analysis.analyzeIfNeeded(
                library: library,
                pendingDeletions: pendingDeletions
            )
        }
    }

    private func restore(_ asset: PHAsset, from decision: SwipeDecision) async {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        restoringCard = RestoringCard(asset: asset, decision: decision)
        await CardRestorationAnimation.run(
            progress: $restorationProgress,
            reduceMotion: reduceMotion
        )
        feedback.impactOccurred()
        restoringCard = nil
        restorationProgress = 0
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
