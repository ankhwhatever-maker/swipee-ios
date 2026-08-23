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
    let onFinished: () -> Void

    @State private var assets: [PHAsset] = []
    @State private var result: DuplicateGroupResult?
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var items: [ReviewSessionItem] {
        duplicateSessions.items(for: group.id)
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
                DuplicateResultView(result: result, onFinished: onFinished)
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
        NavigationStack {
            ZStack {
                Color.swipeeBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("この重複グループ")
                                .font(.title2.bold())
                            Text("写真をタップすると、削除候補とキープを切り替えられます。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                            spacing: 8
                        ) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                reviewCell(asset)
                            }
                        }

                        if assets.count < items.count {
                            Label(
                                "\(items.count - assets.count)枚は現在の写真アクセス範囲外です",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .padding(.bottom, 96)
                }
            }
            .navigationTitle("削除前の確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("仕分けに戻る") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .safeAreaInset(edge: .bottom) { actionArea }
        }
    }

    private func reviewCell(_ asset: PHAsset) -> some View {
        let decision = items.first(where: { $0.assetIdentifier == asset.localIdentifier })?.decision ?? .keep
        let isDeletion = decision == .trash

        return Button {
            toggleDeletion(for: asset, currentDecision: decision)
        } label: {
            ZStack(alignment: .topTrailing) {
                AssetImageView(asset: asset, manager: library.imageManager)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isDeletion ? Color.swipeeDelete : Color.swipeeBorder, lineWidth: isDeletion ? 4 : 1)
                    }
                    .overlay {
                        if isDeletion {
                            Color.black.opacity(0.22)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                Image(systemName: statusIcon(for: decision))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(statusColor(for: decision), in: Circle())
                    .padding(7)
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
        .accessibilityLabel(isDeletion ? "削除候補" : decision == .favorite ? "お気に入り" : "キープ")
        .accessibilityHint("ダブルタップで削除候補を切り替えます")
    }

    private var actionArea: some View {
        VStack(spacing: 8) {
            HStack {
                Label("\(keptCount)枚キープ", systemImage: "checkmark")
                    .foregroundStyle(Color.swipeeKeep)
                Spacer()
                Label("\(deletionCount)枚削除", systemImage: "trash")
                    .foregroundStyle(Color.swipeeDelete)
            }
            .font(.subheadline.bold())

            Button { finishGroup() } label: {
                HStack {
                    if isDeleting { ProgressView().tint(.white) }
                    Text(actionButtonTitle)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(deletionCount > 0 ? Color.swipeeDelete : Color.primary)
            .disabled(isDeleting || assets.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var actionButtonTitle: String {
        if isDeleting { return "削除しています…" }
        if deletionCount == 0 { return "このグループは削除しない" }
        return "\(deletionCount)枚を削除"
    }

    private func loadAssets() {
        assets = library.fetchAssets(localIdentifiers: items.map(\.assetIdentifier))
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
                reviewedGroups.markReviewed(group.id)
                duplicateSessions.clear(groupIdentifier: group.id)
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

    private func statusIcon(for decision: SwipeDecision) -> String {
        switch decision {
        case .trash: return "trash.fill"
        case .keep: return "checkmark"
        case .favorite: return "star.fill"
        }
    }

    private func statusColor(for decision: SwipeDecision) -> Color {
        switch decision {
        case .trash: return .swipeeDelete
        case .keep: return .swipeeKeep
        case .favorite: return .swipeeFavorite
        }
    }
}
