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
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingFilters = false
    @State private var showingSessionReview = false
    @State private var processing = false
    @State private var requestedDecision: SwipeDecision?
    @State private var activeSwipeDecision: SwipeDecision?
    @State private var restoringCard: RestoringCard?
    @State private var restorationProgress: CGFloat = 0
    private let actionOverlayHeight: CGFloat = 76

    private struct RestoringCard {
        let asset: PHAsset
        let decision: SwipeDecision
    }

    private var isDeckVisible: Bool {
        switch library.authorizationStatus {
        case .authorized, .limited:
            return !library.isLoading && !session.isComplete && !library.candidates.isEmpty
        default:
            return false
        }
    }

    private var organizeBackground: Color {
        isDeckVisible ? Color(red: 0.043, green: 0.043, blue: 0.051) : .swipeeBackground
    }

    private var deckControlBackground: Color {
        isDeckVisible ? .white.opacity(0.12) : .swipeeElevatedSurface
    }

    private var deckControlBorder: Color {
        isDeckVisible ? .white.opacity(0.2) : .swipeeBorder
    }

    var body: some View {
        ZStack {
            organizeBackground.ignoresSafeArea()
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
        .sheet(isPresented: $showingFilters) { NavigationStack { PhotoFilterView() } }
        .fullScreenCover(isPresented: $showingSessionReview, onDismiss: {
            Task { await reload() }
        }) {
            ReviewSessionFlowView { }
        }
        .task(id: settings.value.conditionKey) { await authorizeAndLoad() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await reload() } } }
        .alert("操作を完了できませんでした", isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) { Button("OK", role: .cancel) {} } message: { Text(library.errorMessage ?? "") }
    }

    @ViewBuilder private var content: some View {
        switch library.authorizationStatus {
        case .notDetermined: ProgressView("写真へのアクセスを確認しています")
        case .denied, .restricted: permissionDenied
        default:
            if library.isLoading { ProgressView() }
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
                        let restoreOffset = restoration.map {
                            restorationOffset(for: $0.decision, in: proxy.size)
                        } ?? CGSize.zero
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
                        .offset(restoreOffset)
                        .rotationEffect(restoration.map { restorationRotation(for: $0.decision) } ?? .zero)
                        .opacity(restoration != nil && reduceMotion ? restorationProgress : 1)
                        .accessibilityHidden(restoration != nil)
                        .transition(.opacity)
                    }
                }
            }

            actionControls
                .frame(height: actionOverlayHeight)
        }
    }

    private var deckHeader: some View {
        ZStack {
            progressPill
            HStack {
                Spacer()
                filterButton
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 4)
    }

    private var actionControls: some View {
        ZStack {
            HStack(spacing: 32) {
                actionButton("xmark", color: .swipeeDelete, label: "削除候補へ", decision: .trash) { requestedDecision = .trash }
                actionButton("checkmark", color: .swipeeKeep, label: "キープ", decision: .keep) { requestedDecision = .keep }
            }
            HStack {
                undoButton
                    .opacity(activeSwipeDecision == nil ? 1 : 0)
                    .scaleEffect(activeSwipeDecision == nil ? 1 : 0.72)
                Spacer()
            }
        }
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
            Image(systemName: "line.3.horizontal.decrease")
                .font(.headline.bold())
                .frame(width: 44, height: 44)
                .background(deckControlBackground, in: Circle())
                .overlay { Circle().stroke(deckControlBorder, lineWidth: 1) }
        }
        .foregroundStyle(isDeckVisible ? Color.white : Color.primary)
        .accessibilityLabel("表示する写真")
    }

    private var undoButton: some View {
        Button {
            undoLastAction()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.subheadline.bold())
                .frame(width: 34, height: 34)
                .background(deckControlBackground, in: Circle())
                .overlay { Circle().stroke(deckControlBorder) }
                .shadow(color: .black.opacity(!isDeckVisible && colorScheme == .light && canUndoLastAction ? 0.08 : 0), radius: 5, y: 2)
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(isDeckVisible ? Color.white.opacity(0.82) : Color.secondary)
        .opacity(canUndoLastAction ? 1 : 0.28)
        .disabled(processing || !canUndoLastAction)
        .accessibilityLabel("直前の操作を戻す")
        .accessibilityHint("直前に操作した写真をカードへ戻します")
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
                .background(deckControlBackground, in: Circle())
                .overlay { Circle().stroke(deckControlBorder) }
                .foregroundStyle(color)
                .shadow(color: .black.opacity(!isDeckVisible && colorScheme == .light ? 0.1 : 0), radius: 8, y: 4)
        }
        .scaleEffect(activeSwipeDecision == decision ? 1.28 : 1)
        .opacity(activeSwipeDecision == nil || activeSwipeDecision == decision ? 1 : 0)
        .disabled(processing)
        .accessibilityLabel(label)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("この条件の未確認写真は、\nすべて見ました", systemImage: "rectangle.stack.badge.checkmark")
        } description: { Text("表示する写真を変更すると、別の候補を確認できます。") } actions: {
            if canUndoLastAction {
                Button("直前の操作を戻す") { undoLastAction() }
            }
            if !session.items.isEmpty {
                Button("今回の\(session.items.count)枚を確認") {
                    showingSessionReview = true
                }
                .buttonStyle(.borderedProminent)
            }
            Button("表示する写真を変更") { showingFilters = true }.buttonStyle(.borderedProminent)
        }
    }

    private var sessionReadyState: some View {
        ContentUnavailableView {
            Label("\(ReviewSessionStore.targetCount)枚見ました", systemImage: "photo.stack")
        } description: {
            Text("削除する写真を確認して、今回の整理を終えましょう。")
        } actions: {
            if canUndoLastAction {
                Button("直前の操作を戻す") {
                    undoLastAction()
                }
            }
            Button("今回の\(ReviewSessionStore.targetCount)枚を確認") {
                showingSessionReview = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var permissionDenied: some View {
        ContentUnavailableView {
            Label("写真へのアクセスが必要です", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("設定アプリでSwipeeの写真アクセスを許可してください。")
        } actions: {
            Button("設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }.buttonStyle(.borderedProminent)
        }
    }

    private func authorizeAndLoad() async {
        if library.authorizationStatus == .notDetermined { await library.requestAuthorization() }
        session.importPendingRecords(
            pendingDeletions.records.filter { !$0.sourceConditionKey.hasPrefix("duplicates|") }
        )
        await reload()
        if session.isComplete { showingSessionReview = true }
    }
    private func reload() async {
        await library.reload(
            settings: settings.value,
            history: history,
            pendingDeletions: pendingDeletions
        )
    }
    private func decide(_ decision: SwipeDecision, asset: PHAsset) async -> Bool {
        guard !processing, library.candidates.first?.localIdentifier == asset.localIdentifier else { return false }
        processing = true
        if decision == .trash {
            pendingDeletions.enqueue(
                assetIdentifier: asset.localIdentifier,
                sourceConditionKey: settings.value.conditionKey
            )
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

        do {
            let previousFavoriteState = decision == .favorite ? asset.isFavorite : nil
            if decision == .favorite { try await library.markFavorite(asset) }
            history.record(assetIdentifier: asset.localIdentifier, conditionKey: settings.value.conditionKey, decision: decision)
            session.append(
                assetIdentifier: asset.localIdentifier,
                sourceConditionKey: settings.value.conditionKey,
                decision: decision,
                previousFavoriteState: previousFavoriteState
            )
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.12)) {
                library.removeCandidate(asset)
            }
            processing = false
            if session.isComplete { showingSessionReview = true }
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
        guard !processing,
              let action = session.items.last else { return }
        processing = true
        Task {
            let originalDecision = action.originalDecision ?? action.decision
            guard let asset = library.fetchAssets(localIdentifiers: [action.assetIdentifier]).first else {
                if action.decision == .trash {
                    pendingDeletions.remove(assetIdentifier: action.assetIdentifier)
                } else {
                    history.remove(assetIdentifier: action.assetIdentifier, conditionKey: action.sourceConditionKey)
                }
                session.removeLast()
                processing = false
                return
            }

            do {
                if originalDecision == .favorite {
                    try await library.setFavorite(asset, isFavorite: action.previousFavoriteState ?? false)
                }
                switch action.decision {
                case .trash:
                    guard pendingDeletions.remove(assetIdentifier: action.assetIdentifier) != nil else {
                        processing = false
                        return
                    }
                case .keep:
                    guard history.remove(assetIdentifier: action.assetIdentifier, conditionKey: action.sourceConditionKey) != nil else {
                        processing = false
                        return
                    }
                case .favorite:
                    guard history.remove(assetIdentifier: action.assetIdentifier, conditionKey: action.sourceConditionKey) != nil else {
                        processing = false
                        return
                    }
                }

                session.removeLast()
                if settings.value.includes(asset) { await restore(asset, from: originalDecision) }
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
        library.restoreCandidate(asset)

        // Give SwiftUI one render pass at the off-screen position before animating home.
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
        case .trash:
            return CGSize(width: -max(size.width * 1.15, 420) * remaining, height: 18 * remaining)
        case .keep:
            return CGSize(width: max(size.width * 1.15, 420) * remaining, height: 18 * remaining)
        case .favorite:
            return CGSize(width: 0, height: -max(size.height * 1.15, 620) * remaining)
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
}
