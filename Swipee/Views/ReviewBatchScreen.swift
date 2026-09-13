import Photos
import SwiftUI

struct ReviewBatchScreen: View {
    let navigationTitle: String
    let heading: String
    let description: String
    let assets: [PHAsset]
    let expectedItemCount: Int
    let keptCount: Int
    let deletionCount: Int
    let isDeleting: Bool
    let imageManager: PHCachingImageManager
    let backAccessibilityLabel: String
    let excludedItemCount: Int
    let decisionForAsset: (PHAsset) -> SwipeDecision
    let onToggleDeletion: (PHAsset, SwipeDecision) -> Void
    let onBack: () -> Void
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.swipeeBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(heading)
                                .font(.title2.bold())
                            Text(description)
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

                        if excludedItemCount > 0 {
                            Label(
                                "\(excludedItemCount)枚は現在アクセスできないため、確認対象から除外しました",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        if inaccessibleCount > 0 {
                            Label(
                                "\(inaccessibleCount)枚は現在の写真アクセス範囲外です",
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(isDeleting)
                    .accessibilityLabel(backAccessibilityLabel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionArea
            }
        }
    }

    private var inaccessibleCount: Int {
        max(expectedItemCount - assets.count, 0)
    }

    private func reviewCell(_ asset: PHAsset) -> some View {
        let decision = decisionForAsset(asset)
        let isDeletion = decision == .trash

        return Button {
            onToggleDeletion(asset, decision)
        } label: {
            ZStack(alignment: .topTrailing) {
                AssetImageView(asset: asset, manager: imageManager)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isDeletion ? Color.swipeeDelete : Color.swipeeBorder,
                                lineWidth: isDeletion ? 4 : 1
                            )
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
        .accessibilityLabel(isDeletion ? "削除候補" : "キープ")
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

            Button(action: onFinish) {
                HStack {
                    if isDeleting {
                        ProgressView().tint(.white)
                    }
                    Text(actionButtonTitle)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(deletionCount > 0 ? Color.swipeeDelete : Color.primary)
            .disabled(isDeleting || (assets.isEmpty && expectedItemCount > 0))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var actionButtonTitle: String {
        if isDeleting { return "削除しています…" }
        if deletionCount == 0 { return "OK" }
        return "\(deletionCount)枚を削除"
    }

    private func statusIcon(for decision: SwipeDecision) -> String {
        switch decision {
        case .trash: return "trash.fill"
        case .keep: return "checkmark"
        }
    }

    private func statusColor(for decision: SwipeDecision) -> Color {
        switch decision {
        case .trash: return .swipeeDelete
        case .keep: return .swipeeKeep
        }
    }
}
