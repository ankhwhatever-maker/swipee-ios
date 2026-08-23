import Photos
import SwiftUI

private struct ReviewSessionResult {
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
                SessionResultView(
                    result: result,
                    onClose: close,
                    onContinue: closeAndContinue
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
        NavigationStack {
            ZStack {
                Color.swipeeBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("今回見た写真")
                                .font(.title2.bold())
                            Text("削除する写真を最後に確認できます。写真をタップすると選択を切り替えられます。")
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

                        if assets.count < session.items.count {
                            Label(
                                "\(session.items.count - assets.count)枚は現在の写真アクセス範囲外です",
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
            .navigationTitle("今回の確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("仕分けに戻る") { dismiss() }
                        .disabled(isDeleting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionArea
            }
        }
    }

    private func reviewCell(_ asset: PHAsset) -> some View {
        let decision = session.items.first(where: { $0.assetIdentifier == asset.localIdentifier })?.decision ?? .keep
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
                Label("\(session.deletionCount)枚削除", systemImage: "trash")
                    .foregroundStyle(Color.swipeeDelete)
            }
            .font(.subheadline.bold())

            Button { finishSession() } label: {
                HStack {
                    if isDeleting { ProgressView().tint(.white) }
                    Text(actionButtonTitle)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(session.deletionCount > 0 ? Color.swipeeDelete : Color.primary)
            .disabled(isDeleting || assets.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var keptCount: Int {
        session.items.count - session.deletionCount
    }

    private var actionButtonTitle: String {
        if isDeleting { return "削除しています…" }
        if session.deletionCount == 0 { return "今回はここまで" }
        return "\(session.deletionCount)枚を削除"
    }

    private func loadAssets() {
        assets = library.fetchAssets(localIdentifiers: session.items.map(\.assetIdentifier))
    }

    private func toggleDeletion(for asset: PHAsset, currentDecision: SwipeDecision) {
        guard let item = session.items.first(where: { $0.assetIdentifier == asset.localIdentifier }) else { return }

        if currentDecision == .trash {
            let restoredDecision = item.decisionBeforeDeletion ?? .keep
            pendingDeletions.remove(assetIdentifier: asset.localIdentifier)
            history.record(
                assetIdentifier: asset.localIdentifier,
                conditionKey: item.sourceConditionKey,
                decision: restoredDecision
            )
            session.updateDecision(assetIdentifier: asset.localIdentifier, decision: restoredDecision)
        } else {
            history.remove(assetIdentifier: asset.localIdentifier, conditionKey: item.sourceConditionKey)
            pendingDeletions.enqueue(
                assetIdentifier: asset.localIdentifier,
                sourceConditionKey: item.sourceConditionKey
            )
            session.updateDecision(
                assetIdentifier: asset.localIdentifier,
                decision: .trash,
                decisionBeforeDeletion: currentDecision
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

    private func close() {
        dismiss()
        onContinue()
    }

    private func closeAndContinue() {
        dismiss()
        onContinue()
    }
}

private struct SessionResultView: View {
    let result: ReviewSessionResult
    let onClose: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.075, green: 0.067, blue: 0.063).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title.bold())
                            .frame(width: 52, height: 52)
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("閉じる")
                }

                Spacer(minLength: 36)

                Text("今回の整理")
                    .font(.title2.bold())

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(result.deletedCount)")
                        .font(.system(size: 104, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.65)
                    Text("枚")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                }
                .padding(.top, 12)

                Text(result.deletedCount == 0 ? "削除はありません" : "削除しました")
                    .font(.title2.bold())

                HStack(spacing: 14) {
                    resultCard(
                        count: result.keptCount,
                        title: "キープ",
                        icon: "checkmark",
                        color: .swipeeKeep
                    )
                    resultCard(
                        count: result.deletedCount,
                        title: "削除",
                        icon: "trash",
                        color: .swipeeDelete
                    )
                }
                .padding(.top, 48)

                Text("累計 \(result.totalDeletedCount)枚を削除")
                    .font(.title3.bold())
                    .padding(.top, 34)

                Text("削除した写真は、写真アプリの「最近削除した項目」から復元できます。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 10)

                Spacer(minLength: 36)

                Button(action: onContinue) {
                    Text("もう10枚見る")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .foregroundStyle(.white)

                Button("またあとで", action: onClose)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 18)
                    .padding(.bottom, 10)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
    }

    private func resultCard(count: Int, title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Text("\(count)")
                .font(.system(size: 54, weight: .bold, design: .rounded))
            Label(title, systemImage: icon)
                .font(.headline)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
