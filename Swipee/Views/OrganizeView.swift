import Photos
import SwiftUI
import UIKit

struct OrganizeView: View {
    @EnvironmentObject private var settings: CandidateSettingsStore
    @EnvironmentObject private var history: ReviewHistoryStore
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var session: ReviewSessionStore
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingFilters = false
    @State private var showingSessionReview = false
    @State private var processing = false
    @State private var requestedDecision: SwipeDecision?
    @State private var activeSwipeDecision: SwipeDecision?
    @State private var restoringCard: RestoringCard?
    @State private var restorationProgress: CGFloat = 0
    @State private var loadedConditionKey: String?
    @State private var loadedPendingDeletionRevision: Int?
    private let actionOverlayHeight: CGFloat = 76

    private struct RestoringCard {
        let asset: PHAsset
        let decision: SwipeDecision
    }

    private var isDeckVisible: Bool {
        switch library.authorizationStatus {
        case .authorized, .limited:
            return !session.isComplete && !library.candidates.isEmpty
        default:
            return false
        }
    }

    private var deckControlBackground: Color {
        isDeckVisible ? .white.opacity(0.12) : .swipeeElevatedSurface
    }

    private var deckControlBorder: Color {
        isDeckVisible ? .white.opacity(0.2) : .swipeeBorder
    }

    var body: some View {
        ZStack {
            SwipeDeckBackground(
                activeDecision: activeSwipeDecision,
                isDeckVisible: isDeckVisible,
                reduceMotion: reduceMotion
            )
                .ignoresSafeArea()
            content.padding(.horizontal, 10).padding(.bottom, 6)
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topTrailing) {
            if !isDeckVisible {
                filterButton
                    .padding(.top, 8)
                    .padding(.trailing, 14)
            }
        }
        .sheet(isPresented: $showingFilters, onDismiss: {
            Task { await reloadIfNeeded() }
        }) { NavigationStack { PhotoFilterView() } }
        .fullScreenCover(isPresented: $showingSessionReview, onDismiss: {
            Task { await reload() }
        }) {
            ReviewSessionFlowView { }
        }
        .task { await authorizeAndLoad() }
        .onChange(of: settings.value.conditionKey) { _, _ in
            guard !showingFilters else { return }
            Task { await reloadIfNeeded() }
        }
        .onChange(of: history.keptHistoryRevision) { _, _ in
            Task { await reload() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload() } } }
        .alert("お気に入りを変更できませんでした", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(library.errorMessage ?? "") }
    }

    @ViewBuilder private var content: some View {
        switch library.authorizationStatus {
        case .notDetermined: ProgressView("写真へのアクセスを確認しています")
        case .denied, .restricted: PhotoAccessRequiredView()
        default:
            if library.isLoading && library.candidates.isEmpty { ProgressView() }
            else if session.isComplete { sessionReadyState }
            else if library.candidates.isEmpty { emptyState }
            else { deck }
        }
    }

    private var deck: some View {
        VStack(spacing: 0) {
            if library.authorizationStatus == .limited {
                Label("選択した写真のみ表示しています", systemImage: "photo.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.bottom, 6)
            }

            deckHeader

            GeometryReader { proxy in
                ZStack {
                    if let asset = library.candidates.first {
                        let restoration = restoringCard?.asset.localIdentifier == asset.localIdentifier
                            ? restoringCard
                            : nil
                        SwipeCardView(
                            asset: asset,
                            manager: library.imageManager,
                            isInteractive: !processing && !library.isLoading && restoration == nil,
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
                isProcessing: processing || library.isLoading,
                canUndo: canUndoLastAction,
                onDelete: { requestedDecision = .trash },
                onKeep: { requestedDecision = .keep },
                onUndo: undoLastAction
            )
                .frame(height: actionOverlayHeight)
        }
    }

    private var deckHeader: some View {
        ZStack {
            progressPill
            HStack {
                if library.isLoading {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel("写真を更新中")
                }
                Spacer()
                filterButton
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 4)
    }

    private var progressPill: some View {
        Text("\(session.items.count + 1) / \(ReviewSessionStore.targetCount)")
            .font(.caption.bold())
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.swipeePhotoOverlay, in: Capsule())
            .overlay { Capsule().stroke(.white.opacity(0.22), lineWidth: 1) }
            .accessibilityLabel("今回の整理、\(ReviewSessionStore.targetCount)枚中\(session.items.count + 1)枚目")
    }

    private var filterButton: some View {
        Button { showingFilters = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.headline.bold())
                .frame(width: 44, height: 44)
                .background(deckControlBackground, in: Circle())
                .overlay { Circle().stroke(deckControlBorder, lineWidth: 1) }
        }
        .foregroundStyle(isDeckVisible ? Color.white : Color.primary)
        .disabled(library.isLoading)
        .accessibilityLabel("表示する写真")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("この条件の未確認写真は、\nすべて見ました", systemImage: "rectangle.stack.badge.checkmark")
        } description: { Text("表示する写真を変更すると、別の候補を確認できます。") } actions: {
            if !session.items.isEmpty {
                Button("今回の\(session.items.count)枚を確認") {
                    showingSessionReview = true
                }
                .buttonStyle(.borderedProminent)

                Button("表示する写真を変更") {
                    showingFilters = true
                }
                .buttonStyle(.bordered)
            } else {
                Button("表示する写真を変更") {
                    showingFilters = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var sessionReadyState: some View {
        ReviewBatchReadyScreen(itemCount: ReviewSessionStore.targetCount) {
            showingSessionReview = true
        }
    }

    private func authorizeAndLoad() async {
        if library.authorizationStatus == .notDetermined { await library.requestAuthorization() }
        session.importPendingRecords(
            pendingDeletions.records.filter { !$0.sourceConditionKey.hasPrefix("duplicates|") }
        )
        if session.isComplete {
            showingSessionReview = true
            return
        }

        let selectedSettings = settings.value
        await library.reloadIfNeeded(
            settings: selectedSettings,
            history: history,
            pendingDeletions: pendingDeletions
        )
        if settings.value.conditionKey == selectedSettings.conditionKey {
            loadedConditionKey = selectedSettings.conditionKey
            loadedPendingDeletionRevision = pendingDeletions.revision
        }
    }
    private func reload() async {
        let selectedSettings = settings.value
        await library.reload(
            settings: selectedSettings,
            history: history,
            pendingDeletions: pendingDeletions
        )
        if settings.value.conditionKey == selectedSettings.conditionKey {
            loadedConditionKey = selectedSettings.conditionKey
            loadedPendingDeletionRevision = pendingDeletions.revision
        }
    }

    private func reloadIfNeeded() async {
        guard library.authorizationStatus == .authorized || library.authorizationStatus == .limited else { return }
        guard loadedConditionKey != settings.value.conditionKey ||
                loadedPendingDeletionRevision != pendingDeletions.revision else { return }
        await reload()
    }
    private func decide(_ decision: SwipeDecision, asset: PHAsset) async -> Bool {
        guard !processing, !library.isLoading,
              library.candidates.first?.localIdentifier == asset.localIdentifier else { return false }
        processing = true
        if decision == .trash {
            pendingDeletions.enqueue(
                assetIdentifier: asset.localIdentifier,
                sourceConditionKey: settings.value.conditionKey
            )
            loadedPendingDeletionRevision = pendingDeletions.revision
            session.append(
                assetIdentifier: asset.localIdentifier,
                sourceConditionKey: settings.value.conditionKey,
                decision: .trash
            )
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.12)) {
                library.removeCandidate(asset)
            }
            processing = false
            if session.isComplete { showingSessionReview = true }
            return true
        }

        history.record(assetIdentifier: asset.localIdentifier, conditionKey: settings.value.conditionKey, decision: .keep)
        session.append(
            assetIdentifier: asset.localIdentifier,
            sourceConditionKey: settings.value.conditionKey,
            decision: .keep
        )
        withAnimation(reduceMotion ? nil : .easeIn(duration: 0.12)) {
            library.removeCandidate(asset)
        }
        processing = false
        if session.isComplete { showingSessionReview = true }
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

    private var canUndoLastAction: Bool {
        guard let lastAction = session.items.last else { return false }
        if lastAction.decision == .trash {
            return pendingDeletions.contains(assetIdentifier: lastAction.assetIdentifier)
        }
        return history.hasReviewed(
            assetIdentifier: lastAction.assetIdentifier,
            conditionKey: lastAction.sourceConditionKey
        )
    }

    private func undoLastAction() {
        guard !processing, !library.isLoading,
              let action = session.items.last else { return }
        processing = true
        Task {
            guard let asset = library.fetchAssets(localIdentifiers: [action.assetIdentifier]).first else {
                if action.decision == .trash {
                    pendingDeletions.remove(assetIdentifier: action.assetIdentifier)
                    loadedPendingDeletionRevision = pendingDeletions.revision
                } else {
                    history.remove(assetIdentifier: action.assetIdentifier, conditionKey: action.sourceConditionKey)
                }
                session.removeLast()
                processing = false
                return
            }

            switch action.decision {
            case .trash:
                guard pendingDeletions.remove(assetIdentifier: action.assetIdentifier) != nil else {
                    processing = false
                    return
                }
                loadedPendingDeletionRevision = pendingDeletions.revision
            case .keep:
                guard history.remove(assetIdentifier: action.assetIdentifier, conditionKey: action.sourceConditionKey) != nil else {
                    processing = false
                    return
                }
            }

            session.removeLast()
            if settings.value.includes(asset) { await restore(asset, from: action.decision) }
            processing = false
        }
    }

    private func restore(_ asset: PHAsset, from decision: SwipeDecision) async {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        restoringCard = RestoringCard(asset: asset, decision: decision)
        library.restoreCandidate(asset)
        await CardRestorationAnimation.run(
            progress: $restorationProgress,
            reduceMotion: reduceMotion
        )

        feedback.impactOccurred()
        restoringCard = nil
        restorationProgress = 0
    }

}
