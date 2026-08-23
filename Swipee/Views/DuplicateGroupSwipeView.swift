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
    @State private var restoringCard: RestoringCard?
    @State private var restorationProgress: CGFloat = 0
    @State private var cachedAssets: [PHAsset] = []
    private let actionOverlayHeight: CGFloat = 76

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

    var body: some View {
        ZStack {
            Color.swipeeBackground.ignoresSafeArea()
            if assets.isEmpty {
                ProgressView()
            } else if remainingAssets.isEmpty {
                readyState
            } else {
                deck
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .navigationTitle("重複候補")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            assets = library.fetchAssets(localIdentifiers: group.assetIdentifiers)
            updateImageCache()
            if !assets.isEmpty, remainingAssets.isEmpty { showingReview = true }
        }
        .onDisappear { stopImageCache() }
        .fullScreenCover(isPresented: $showingReview, onDismiss: {
            if reviewFinished {
                dismiss()
                Task {
                    await analysis.analyzeIfNeeded(
                        library: library,
                        pendingDeletions: pendingDeletions
                    )
                }
            }
        }) {
            DuplicateGroupReviewView(group: group) {
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
        VStack(spacing: 10) {
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
                            metadataBottomInset: actionOverlayHeight,
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
            .overlay(alignment: .top) { progressPill.padding(.top, 12) }
            .overlay(alignment: .bottom) { actionControls.padding(.vertical, 4) }
        }
    }

    private var actionControls: some View {
        ZStack {
            HStack(spacing: 32) {
                actionButton("xmark", color: .swipeeDelete, label: "削除候補へ", decision: .trash) {
                    requestedDecision = .trash
                }
                actionButton("checkmark", color: .swipeeKeep, label: "キープ", decision: .keep) {
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
        ContentUnavailableView {
            Label("このグループをすべて見ました", systemImage: "square.on.square")
        } description: {
            Text("削除する写真を最後に確認できます。")
        } actions: {
            if canUndo {
                Button("直前の操作を戻す") { undoLastAction() }
            }
            Button("\(group.count)枚を確認") { showingReview = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var progressPill: some View {
        Text("\(min(items.count + 1, group.count)) / \(group.count)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.swipeePhotoOverlay, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.22)) }
            .accessibilityLabel("重複候補、\(group.count)枚中\(min(items.count + 1, group.count))枚目")
    }

    private var undoButton: some View {
        Button { undoLastAction() } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.subheadline.bold())
                .frame(width: 34, height: 34)
                .background(Color.swipeeElevatedSurface, in: Circle())
                .overlay { Circle().stroke(Color.swipeeBorder) }
                .shadow(color: .black.opacity(colorScheme == .light && canUndo ? 0.08 : 0), radius: 5, y: 2)
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(.secondary)
        .opacity(canUndo ? 1 : 0.28)
        .disabled(processing || !canUndo)
        .accessibilityLabel("直前の操作を戻す")
    }

    private func actionButton(
        _ icon: String,
        color: Color,
        label: String,
        decision: SwipeDecision,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title2.bold())
                .frame(width: 58, height: 58)
                .background(Color.swipeeElevatedSurface, in: Circle())
                .overlay { Circle().stroke(Color.swipeeBorder) }
                .foregroundStyle(color)
                .shadow(color: .black.opacity(colorScheme == .light ? 0.1 : 0), radius: 8, y: 4)
        }
        .scaleEffect(activeSwipeDecision == decision ? 1.28 : 1)
        .opacity(activeSwipeDecision == nil || activeSwipeDecision == decision ? 1 : 0)
        .disabled(processing)
        .accessibilityLabel(label)
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
            if remainingAssets.isEmpty { showingReview = true }
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
        guard let action = items.last else { return false }
        if action.decision == .trash {
            return pendingDeletions.contains(assetIdentifier: action.assetIdentifier)
        }
        return true
    }

    private func undoLastAction() {
        guard !processing, let action = items.last else { return }
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
