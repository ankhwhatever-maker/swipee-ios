import Photos
import SwiftUI

struct DuplicateGroupResult {
    let keptCount: Int
    let deletedCount: Int
    let totalDeletedCount: Int
}

struct DuplicateGroupReviewView: View {
    @EnvironmentObject private var duplicateSessions: DuplicateSessionStore
    @EnvironmentObject private var reviewedGroups: DuplicateReviewedStore
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var reviewSession: ReviewSessionStore
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss

    let group: DuplicatePhotoGroup
    let batchAssetIdentifiers: [String]
    let isFinalBatch: Bool
    let onFinished: () -> Void

    @State private var assets: [PHAsset] = []
    @State private var result: DuplicateGroupResult?
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var items: [ReviewSessionItem] {
        let itemsByIdentifier = Dictionary(
            uniqueKeysWithValues: duplicateSessions.items(for: group.id).map { ($0.assetIdentifier, $0) }
        )
        return batchAssetIdentifiers.compactMap { itemsByIdentifier[$0] }
    }

    private var deletionCount: Int {
        items.filter { $0.decision == .trash }.count
    }

    private var keptCount: Int {
        items.count - deletionCount
    }

    var body: some View {
        Group {
            if let result {
                DuplicateResultView(
                    result: result,
                    continuesCurrentGroup: !isFinalBatch,
                    onFinished: onFinished
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
            navigationTitle: "重複内容の確認",
            heading: "この重複グループ",
            description: "写真をタップすると、削除候補とキープを切り替えられます。",
            assets: assets,
            expectedItemCount: items.count,
            keptCount: keptCount,
            deletionCount: deletionCount,
            isDeleting: isDeleting,
            imageManager: library.imageManager,
            decisionForAsset: { asset in
                items.first {
                    $0.assetIdentifier == asset.localIdentifier
                }?.decision ?? .keep
            },
            onToggleDeletion: { asset, decision in
                toggleDeletion(for: asset, currentDecision: decision)
            },
            onBack: { dismiss() },
            onFinish: finishGroup
        )
    }

    private func loadAssets() {
        assets = library.fetchAssets(localIdentifiers: batchAssetIdentifiers)
    }

    private func toggleDeletion(for asset: PHAsset, currentDecision: SwipeDecision) {
        guard let item = items.first(where: { $0.assetIdentifier == asset.localIdentifier }) else { return }

        if currentDecision == .trash {
            pendingDeletions.remove(assetIdentifier: asset.localIdentifier)
            duplicateSessions.updateDecision(
                groupIdentifier: group.id,
                assetIdentifier: asset.localIdentifier,
                decision: item.decisionBeforeDeletion ?? item.originalDecision ?? .keep
            )
        } else {
            pendingDeletions.enqueue(
                assetIdentifier: asset.localIdentifier,
                sourceConditionKey: item.sourceConditionKey
            )
            duplicateSessions.updateDecision(
                groupIdentifier: group.id,
                assetIdentifier: asset.localIdentifier,
                decision: .trash,
                decisionBeforeDeletion: currentDecision
            )
        }
    }

    private func finishGroup() {
        guard !isDeleting else { return }
        let snapshot = items
        let deletionItems = snapshot.filter { $0.decision == .trash }
        let deletionIdentifiers = Set(deletionItems.map(\.assetIdentifier))
        let assetsToDelete = assets.filter { deletionIdentifiers.contains($0.localIdentifier) }

        guard assetsToDelete.count == deletionItems.count else {
            errorMessage = "削除候補の一部にアクセスできません。写真へのアクセス範囲を確認してください。"
            return
        }

        isDeleting = true
        Task {
            do {
                if !assetsToDelete.isEmpty {
                    try await library.deleteAssets(assetsToDelete)
                    pendingDeletions.remove(assetIdentifiers: deletionIdentifiers)
                }

                let deleted = deletionItems.count
                reviewSession.recordDeleted(count: deleted)
                if isFinalBatch {
                    reviewedGroups.markReviewed(group.id)
                    duplicateSessions.clear(groupIdentifier: group.id)
                } else {
                    duplicateSessions.markCurrentBatchCompleted(
                        groupIdentifier: group.id,
                        itemCount: snapshot.count
                    )
                }
                result = DuplicateGroupResult(
                    keptCount: snapshot.count - deleted,
                    deletedCount: deleted,
                    totalDeletedCount: reviewSession.totalDeletedCount
                )
            } catch {
                if !PhotoLibraryService.isUserCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
            isDeleting = false
        }
    }

}
