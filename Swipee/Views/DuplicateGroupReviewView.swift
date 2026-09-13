import Photos
import SwiftUI

struct DuplicateGroupResult {
    let keptCount: Int
    let deletedCount: Int
    let deletedDataSize: Int64?
    let totalDeletedCount: Int
}

struct DuplicateGroupReviewView: View {
    @EnvironmentObject private var duplicateSessions: DuplicateSessionStore
    @EnvironmentObject private var reviewedGroups: DuplicateReviewedStore
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var reviewSession: ReviewSessionStore
    @EnvironmentObject private var library: PhotoLibraryService

    let group: DuplicatePhotoGroup
    let batchAssetIdentifiers: [String]
    let isFinalBatch: Bool
    let onBack: () -> Void
    let onPrimaryAction: () -> Void

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
                ReviewResultScreen(
                    title: "重複",
                    keptCount: result.keptCount,
                    deletedCount: result.deletedCount,
                    deletedDataSize: result.deletedDataSize,
                    totalDeletedCount: result.totalDeletedCount,
                    primaryButtonTitle: isFinalBatch ? "重複候補へ戻る" : "次の写真を見る",
                    onPrimaryAction: onPrimaryAction
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
            backAccessibilityLabel: "重複整理に戻る",
            decisionForAsset: { asset in
                items.first {
                    $0.assetIdentifier == asset.localIdentifier
                }?.decision ?? .keep
            },
            onToggleDeletion: { asset, decision in
                toggleDeletion(for: asset, currentDecision: decision)
            },
            onBack: onBack,
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
                decision: .keep
            )
        } else {
            pendingDeletions.enqueue(
                assetIdentifier: asset.localIdentifier,
                sourceConditionKey: item.sourceConditionKey
            )
            duplicateSessions.updateDecision(
                groupIdentifier: group.id,
                assetIdentifier: asset.localIdentifier,
                decision: .trash
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
                let deletedDataSize: Int64?
                if assetsToDelete.isEmpty {
                    deletedDataSize = nil
                } else {
                    deletedDataSize = try? await PhotoAssetSizeService.shared.totalSize(for: assetsToDelete)
                }

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
                    deletedDataSize: deletedDataSize,
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
