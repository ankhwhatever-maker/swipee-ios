import Photos
import SwiftUI

struct ReviewSessionResult {
    let reviewedCount: Int
    let keptCount: Int
    let deletedCount: Int
    let totalDeletedCount: Int
}

struct ReviewSessionFlowView: View {
    @EnvironmentObject private var history: ReviewHistoryStore
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var session: ReviewSessionStore
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var result: ReviewSessionResult?
    @State private var isDeleting = false
    @State private var errorMessage: String?

    let onContinue: () -> Void

    var body: some View {
        Group {
            if let result {
                ReviewResultScreen(
                    title: "今回の整理",
                    keptCount: result.keptCount,
                    deletedCount: result.deletedCount,
                    totalDeletedCount: result.totalDeletedCount,
                    primaryButtonTitle: "もう\(ReviewSessionStore.targetCount)枚見る",
                    onClose: close,
                    onPrimaryAction: closeAndContinue
                )
            } else {
                reviewScreen
            }
        }
        .task { loadAssets() }
        .alert("操作を完了できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private var reviewScreen: some View {
        ReviewBatchScreen(
            navigationTitle: "整理内容の確認",
            heading: "今回見た写真",
            description: "削除する写真を最後に確認できます。写真をタップすると選択を切り替えられます。",
            assets: assets,
            expectedItemCount: session.items.count,
            keptCount: keptCount,
            deletionCount: session.deletionCount,
            isDeleting: isDeleting,
            imageManager: library.imageManager,
            decisionForAsset: { asset in
                session.items.first {
                    $0.assetIdentifier == asset.localIdentifier
                }?.decision ?? .keep
            },
            onToggleDeletion: { asset, decision in
                toggleDeletion(for: asset, currentDecision: decision)
            },
            onBack: { dismiss() },
            onFinish: finishSession
        )
    }

    private var keptCount: Int {
        session.items.count - session.deletionCount
    }

    private func loadAssets() {
        assets = library.fetchAssets(localIdentifiers: session.items.map(\.assetIdentifier))
    }

    private func toggleDeletion(for asset: PHAsset, currentDecision: SwipeDecision) {
        guard let item = session.items.first(where: { $0.assetIdentifier == asset.localIdentifier }) else { return }

        if currentDecision == .trash {
            pendingDeletions.remove(assetIdentifier: asset.localIdentifier)
            history.record(
                assetIdentifier: asset.localIdentifier,
                conditionKey: item.sourceConditionKey,
                decision: .keep
            )
            session.updateDecision(assetIdentifier: asset.localIdentifier, decision: .keep)
        } else {
            history.remove(assetIdentifier: asset.localIdentifier, conditionKey: item.sourceConditionKey)
            pendingDeletions.enqueue(
                assetIdentifier: asset.localIdentifier,
                sourceConditionKey: item.sourceConditionKey
            )
            session.updateDecision(
                assetIdentifier: asset.localIdentifier,
                decision: .trash
            )
        }
    }

    private func finishSession() {
        guard !isDeleting else { return }
        let snapshot = session.items
        let deletionItems = snapshot.filter { $0.decision == .trash }
        let deletionIDs = Set(deletionItems.map(\.assetIdentifier))
        let assetsToDelete = assets.filter { deletionIDs.contains($0.localIdentifier) }

        guard assetsToDelete.count == deletionItems.count else {
            errorMessage = "削除候補の一部にアクセスできません。写真へのアクセス範囲を確認してください。"
            return
        }

        isDeleting = true
        Task {
            do {
                if !assetsToDelete.isEmpty {
                    try await library.deleteAssets(assetsToDelete)
                    for item in deletionItems {
                        history.record(
                            assetIdentifier: item.assetIdentifier,
                            conditionKey: item.sourceConditionKey,
                            decision: .trash
                        )
                    }
                    pendingDeletions.remove(assetIdentifiers: deletionIDs)
                }

                let deletedCount = deletionItems.count
                let reviewedCount = snapshot.count
                session.finish(deletedCount: deletedCount)
                result = ReviewSessionResult(
                    reviewedCount: reviewedCount,
                    keptCount: reviewedCount - deletedCount,
                    deletedCount: deletedCount,
                    totalDeletedCount: session.totalDeletedCount
                )
            } catch {
                if !PhotoLibraryService.isUserCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
            isDeleting = false
        }
    }

    private func close() {
        dismiss()
        onContinue()
    }

    private func closeAndContinue() {
        dismiss()
        onContinue()
    }
}
