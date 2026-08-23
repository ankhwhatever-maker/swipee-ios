import Photos
import SwiftUI
import UIKit

struct DuplicatesView: View {
    @EnvironmentObject private var analysis: DuplicateAnalysisService
    @EnvironmentObject private var reviewed: DuplicateReviewedStore
    @EnvironmentObject private var pendingDeletions: PendingDeletionStore
    @EnvironmentObject private var library: PhotoLibraryService

    @State private var assetsByIdentifier: [String: PHAsset] = [:]

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    private var visibleGroups: [DuplicatePhotoGroup] {
        analysis.groups.filter { !reviewed.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Color.swipeeBackground.ignoresSafeArea()
            content
        }
        .navigationTitle("重複候補")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("再解析", systemImage: "arrow.clockwise") {
                        Task { await analyze(force: true) }
                    }
                    Button("確認済みを再表示", systemImage: "eye") {
                        reviewed.clear()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("重複候補メニュー")
            }
        }
        .task { await authorizeAndAnalyze() }
        .onChange(of: analysis.groups) { _, _ in loadAssets() }
        .refreshable { await analyze(force: true) }
        .alert("解析を完了できませんでした", isPresented: Binding(
            get: { analysis.errorMessage != nil },
            set: { if !$0 { analysis.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(analysis.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch library.authorizationStatus {
        case .notDetermined:
            ProgressView("写真へのアクセスを確認しています")
        case .denied, .restricted:
            permissionDenied
        default:
            if visibleGroups.isEmpty, analysis.isAnalyzing {
                analysisProgress
            } else if visibleGroups.isEmpty {
                emptyState
            } else {
                groupGrid
            }
        }
    }

    private var groupGrid: some View {
        ScrollView {
            VStack(spacing: 12) {
                if analysis.isAnalyzing { compactProgress }
                if library.authorizationStatus == .limited {
                    Label("選択した写真のみ解析しています", systemImage: "photo.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(visibleGroups) { group in
                        NavigationLink(value: group) {
                            DuplicateGroupCell(
                                group: group,
                                assets: group.assetIdentifiers.compactMap { assetsByIdentifier[$0] },
                                manager: library.imageManager
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationDestination(for: DuplicatePhotoGroup.self) { group in
            DuplicateGroupSwipeView(group: group)
        }
    }

    private var analysisProgress: some View {
        VStack(spacing: 16) {
            ProgressView(value: Double(analysis.analyzedCount), total: Double(max(analysis.totalCount, 1)))
                .frame(maxWidth: 240)
            Text("似ている写真を確認しています")
                .font(.headline)
            Text("\(analysis.analyzedCount) / \(analysis.totalCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var compactProgress: some View {
        VStack(spacing: 5) {
            ProgressView(value: Double(analysis.analyzedCount), total: Double(max(analysis.totalCount, 1)))
            Text("写真を解析中 \(analysis.analyzedCount) / \(analysis.totalCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("重複候補はありません", systemImage: "square.on.square")
        } description: {
            Text("現在アクセスできる写真から、よく似た組み合わせは見つかりませんでした。")
        } actions: {
            Button("もう一度解析") {
                Task { await analyze(force: true) }
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
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func authorizeAndAnalyze() async {
        if library.authorizationStatus == .notDetermined { await library.requestAuthorization() }
        await analyze(force: false)
    }

    private func analyze(force: Bool) async {
        await analysis.analyzeIfNeeded(
            library: library,
            pendingDeletions: pendingDeletions,
            force: force
        )
        loadAssets()
    }

    private func loadAssets() {
        let identifiers = Array(Set(analysis.groups.flatMap(\.assetIdentifiers)))
        assetsByIdentifier = Dictionary(
            uniqueKeysWithValues: library.fetchAssets(localIdentifiers: identifiers)
                .map { ($0.localIdentifier, $0) }
        )
    }
}

private struct DuplicateGroupCell: View {
    let group: DuplicatePhotoGroup
    let assets: [PHAsset]
    let manager: PHCachingImageManager

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                ForEach(Array(assets.prefix(3).enumerated()).reversed(), id: \.element.localIdentifier) { index, asset in
                    AssetImageView(asset: asset, manager: manager)
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.swipeeBorder) }
                        .rotationEffect(.degrees(index == 0 ? 0 : (index.isMultiple(of: 2) ? 3 : -3)))
                        .offset(y: CGFloat(index) * -5)
                }
            }
            .padding(.top, 10)

            Text("\(group.count)")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 46, minHeight: 46)
                .background(.black.opacity(0.84), in: Circle())
                .padding(10)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("似ている写真、\(group.count)枚")
    }
}
