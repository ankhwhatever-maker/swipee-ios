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
    @State private var excludedItemCount = 0
    @State private var isGroupReviewable: Bool?

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
                    title: "整理結果",
                    keptCount: result.keptCount,
                    deletedCount: result.deletedCount,
                    deletedDataSize: result.deletedDataSize,
                    totalDeletedCount: result.totalDeletedCount,
                    primaryButtonTitle: isFinalBatch ? "重複候補へ戻る" : "次の写真を見る",
                    onPrimaryAction: onPrimaryAction
                )
            } else if isGroupReviewable == false {
                insufficientGroupState
            } else if isGroupReviewable == nil {
                ProgressView()
            } else {
                reviewScreen
            }
        }
        .task { loadAssets() }
        .alert("写真を削除できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .interactiveDismissDisabled()
    }

    private var reviewScreen: some View {
        ReviewBatchScreen(
            navigationTitle: "重複内容の確認",
            heading: "削除対象の確認",
            description: "写真をタップすると、削除候補とキープを切り替えられます。",
            assets: assets,
            expectedItemCount: items.count,
            keptCount: keptCount,
            deletionCount: deletionCount,
            isDeleting: isDeleting,
            imageManager: library.imageManager,
            backAccessibilityLabel: "重複整理に戻る",
            excludedItemCount: excludedItemCount,
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

    private var insufficientGroupState: some View {
        NavigationStack {
            ZStack {
                Color.swipeeBackground.ignoresSafeArea()
                ContentUnavailableView {
                    Label("この重複グループは確認できません", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("現在アクセスできる写真が2枚未満になりました。")
                } actions: {
                    Button("重複候補へ戻る", action: onBack)
                        .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("重複内容の確認")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func loadAssets() {
        reconcileUnavailableItems()
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
        reconcileUnavailableItems()
        guard isGroupReviewable != false else { return }
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

    private func reconcileUnavailableItems() {
        let currentItems = items
        let accessibleGroupAssets = library.fetchAssets(
            localIdentifiers: group.assetIdentifiers
        )
        isGroupReviewable = accessibleGroupAssets.count >= 2
        let fetchedAssets = library.fetchAssets(
            localIdentifiers: currentItems.map(\.assetIdentifier)
        )
        let availableIdentifiers = Set(fetchedAssets.map(\.localIdentifier))
        let unavailableIdentifiers = Set(
            currentItems.lazy
                .map(\.assetIdentifier)
                .filter { !availableIdentifiers.contains($0) }
        )

        if isGroupReviewable == false {
            pendingDeletions.remove(
                assetIdentifiers: Set(currentItems.map(\.assetIdentifier))
            )
            duplicateSessions.clear(groupIdentifier: group.id)
            reviewedGroups.markReviewed(group.id)
            excludedItemCount += unavailableIdentifiers.count
            assets = fetchedAssets
            return
        }

        guard !unavailableIdentifiers.isEmpty else {
            assets = fetchedAssets
            return
        }

        pendingDeletions.remove(assetIdentifiers: unavailableIdentifiers)
        duplicateSessions.remove(
            assetIdentifiers: unavailableIdentifiers,
            groupIdentifier: group.id
        )
        excludedItemCount += unavailableIdentifiers.count
        assets = fetchedAssets
    }

}
