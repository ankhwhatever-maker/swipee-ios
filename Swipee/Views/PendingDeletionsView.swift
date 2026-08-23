import Photos
import SwiftUI
import UIKit

struct PendingDeletionsView: View {
    @EnvironmentObject private var history: ReviewHistoryStore
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var library: PhotoLibraryService
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var inaccessibleCount: Int {
        max(pendingDeletions.records.count - assets.count, 0)
    }

    var body: some View {
        Group {
            if pendingDeletions.records.isEmpty {
                ContentUnavailableView("削除候補はありません", systemImage: "trash")
            } else if assets.isEmpty {
                ContentUnavailableView {
                    Label("削除候補にアクセスできません", systemImage: "photo.badge.exclamationmark")
                } description: {
                    Text("写真へのアクセス範囲を確認してください。削除候補の記録は保持されています。")
                } actions: {
                    Button("設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if inaccessibleCount > 0 {
                        Section {
                            Label("\(inaccessibleCount)枚は現在のアクセス範囲外です", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(Color.swipeeFavorite)
                        }
                    }
                    Section {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            pendingRow(asset)
                        }
                    } footer: {
                        Text("ここから外した写真はキープとして記録され、同じ条件では再表示されません。")
                    }
                }
            }
        }
        .navigationTitle("削除候補")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("閉じる")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !pendingDeletions.records.isEmpty {
                    Button("すべてキープ") { keepAll() }
                        .tint(.swipeeKeep)
                        .disabled(isDeleting)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !assets.isEmpty {
                Button { deleteAll() } label: {
                    HStack {
                        if isDeleting { ProgressView().tint(.white) }
                        Text(isDeleting ? "削除しています…" : deleteButtonTitle)
                    }
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.swipeeDelete)
                .disabled(isDeleting)
                .padding()
                .background(.bar)
            }
        }
        .task {
            library.refreshAuthorizationStatus()
            loadAssets()
        }
        .alert("削除できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .interactiveDismissDisabled(isDeleting)
    }

    private func pendingRow(_ asset: PHAsset) -> some View {
        HStack(spacing: 14) {
            AssetImageView(asset: asset, manager: library.imageManager)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.mediaType == .video ? "動画" : "写真")
                    .font(.headline)
                if let date = asset.creationDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("キープ") { keep(asset) }
                .buttonStyle(.bordered)
                .tint(.swipeeKeep)
                .disabled(isDeleting)
        }
        .padding(.vertical, 4)
    }

    private func loadAssets() {
        assets = library.fetchAssets(
            localIdentifiers: pendingDeletions.records.map(\.assetIdentifier)
        )
        if library.authorizationStatus == .authorized {
            pendingDeletions.reconcile(
                validAssetIdentifiers: Set(assets.map(\.localIdentifier))
            )
        }
    }

    private func keep(_ asset: PHAsset) {
        guard let record = pendingDeletions.remove(assetIdentifier: asset.localIdentifier) else { return }
        history.record(
            assetIdentifier: record.assetIdentifier,
            conditionKey: record.sourceConditionKey,
            decision: .keep
        )
        assets.removeAll { $0.localIdentifier == asset.localIdentifier }
    }

    private func keepAll() {
        for record in pendingDeletions.records {
            history.record(
                assetIdentifier: record.assetIdentifier,
                conditionKey: record.sourceConditionKey,
                decision: .keep
            )
        }
        pendingDeletions.removeAll()
        assets.removeAll()
    }

    private func deleteAll() {
        guard !isDeleting, !assets.isEmpty else { return }
        isDeleting = true
        let assetsToDelete = assets
        let identifiers = Set(assetsToDelete.map(\.localIdentifier))

        Task {
            do {
                try await library.deleteAssets(assetsToDelete)
                for record in pendingDeletions.records where identifiers.contains(record.assetIdentifier) {
                    history.record(
                        assetIdentifier: record.assetIdentifier,
                        conditionKey: record.sourceConditionKey,
                        decision: .trash
                    )
                }
                pendingDeletions.remove(assetIdentifiers: identifiers)
                assets.removeAll()
                if pendingDeletions.records.isEmpty { dismiss() }
            } catch {
                if !PhotoLibraryService.isUserCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
            isDeleting = false
        }
    }

    private var deleteButtonTitle: String {
        if inaccessibleCount > 0 {
            return "アクセス可能な\(assets.count)枚を削除"
        }
        return "\(assets.count)枚を削除"
    }
}
