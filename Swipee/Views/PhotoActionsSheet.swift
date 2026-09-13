@preconcurrency import Photos
import SwiftUI

struct PhotoActionsSheet: View {
    let asset: PHAsset
    let isFavorite: Bool
    let isUpdatingFavorite: Bool
    let onToggleFavorite: () -> Void
    let onShare: () -> Void
    let onAlbumAdded: (String) -> Void
    let onBackgroundRemoved: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    NavigationLink {
                        PhotoAlbumPickerView(asset: asset, onAdded: onAlbumAdded)
                    } label: {
                        actionTile(
                            title: "アルバムに追加",
                            icon: "rectangle.stack.badge.plus"
                        )
                    }
                    .buttonStyle(.plain)

                    if asset.mediaType == .image {
                        NavigationLink {
                            BackgroundRemovalView(asset: asset, onSaved: onBackgroundRemoved)
                        } label: {
                            actionTile(title: "背景を削除", icon: "person.crop.rectangle")
                        }
                        .buttonStyle(.plain)
                    } else {
                        restrictedTile(
                            title: "背景を削除",
                            icon: "person.crop.rectangle",
                            restriction: "写真のみ"
                        )
                    }

#if DEBUG
                    unavailableTile(title: "自動補正", icon: "wand.and.sparkles")
                    unavailableTile(title: "圧縮する", icon: "arrow.down.right.and.arrow.up.left")
#endif

                    Button(action: onToggleFavorite) {
                        actionTile(
                            title: isFavorite ? "お気に入りから外す" : "お気に入りに追加",
                            icon: isFavorite ? "heart.fill" : "heart"
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isUpdatingFavorite)

                    Button(action: onShare) {
                        actionTile(title: "共有", icon: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(Color.swipeeBackground)
            .navigationTitle("写真の操作")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func actionTile(title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 25, weight: .medium))
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(Color.swipeeElevatedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.swipeeBorder, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func unavailableTile(title: String, icon: String) -> some View {
        restrictedTile(title: title, icon: icon, restriction: "準備中")
    }

    private func restrictedTile(title: String, icon: String, restriction: String) -> some View {
        ZStack(alignment: .topTrailing) {
            actionTile(title: title, icon: icon)
                .opacity(0.48)

            Text(restriction)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
                .padding(8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)、\(restriction)")
    }
}

private struct PhotoAlbumPickerView: View {
    let asset: PHAsset
    let onAdded: (String) -> Void

    @State private var albums: [PhotoAlbumOption] = []
    @State private var isLoading = true
    @State private var addingAlbumIdentifier: String?
    @State private var showingNewAlbumPrompt = false
    @State private var newAlbumName = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if albums.isEmpty {
                ContentUnavailableView {
                    Label("追加できるアルバムがありません", systemImage: "rectangle.stack")
                } description: {
                    Text("新しいアルバムを作成できます。")
                }
            } else {
                List(albums) { album in
                    Button {
                        add(to: album)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "rectangle.stack")
                                .foregroundStyle(.secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title)
                                    .foregroundStyle(.primary)
                                Text("\(album.assetCount)枚")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if album.containsAsset {
                                Label("追加済み", systemImage: "checkmark")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if addingAlbumIdentifier == album.id {
                                ProgressView()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(album.containsAsset || addingAlbumIdentifier != nil)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("アルバムに追加")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newAlbumName = ""
                    showingNewAlbumPrompt = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新しいアルバムを作成")
                .disabled(addingAlbumIdentifier != nil)
            }
        }
        .task { loadAlbums() }
        .alert("新しいアルバム", isPresented: $showingNewAlbumPrompt) {
            TextField("アルバム名", text: $newAlbumName)
            Button("キャンセル", role: .cancel) {}
            Button("作成") { createAlbum() }
                .disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("作成したアルバムに、この写真を追加します。")
        }
        .alert("アルバムに追加できませんでした", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadAlbums() {
        let result = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var loadedAlbums: [PhotoAlbumOption] = []
        result.enumerateObjects { collection, _, _ in
            guard collection.canPerform(.addContent),
                  let title = collection.localizedTitle,
                  !title.isEmpty else { return }
            let assets = PHAsset.fetchAssets(in: collection, options: nil)
            loadedAlbums.append(PhotoAlbumOption(
                collection: collection,
                title: title,
                assetCount: assets.count,
                containsAsset: assets.index(of: asset) != NSNotFound
            ))
        }
        albums = loadedAlbums.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        isLoading = false
    }

    private func add(to album: PhotoAlbumOption) {
        guard addingAlbumIdentifier == nil else { return }
        addingAlbumIdentifier = album.id
        Task {
            do {
                try await addAsset(to: album.collection)
                onAdded(album.title)
            } catch {
                errorMessage = error.localizedDescription
                addingAlbumIdentifier = nil
            }
        }
    }

    private func createAlbum() {
        let title = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, addingAlbumIdentifier == nil else { return }
        addingAlbumIdentifier = "new-album"
        Task {
            do {
                let collection = try await createAlbum(named: title)
                try await addAsset(to: collection)
                onAdded(title)
            } catch {
                errorMessage = error.localizedDescription
                addingAlbumIdentifier = nil
            }
        }
    }

    private func addAsset(to collection: PHAssetCollection) async throws {
        var didRequestChange = false
        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            didRequestChange = true
            request.addAssets([asset] as NSArray)
        }
        guard didRequestChange else {
            throw PhotoAlbumError.albumUnavailable
        }
    }

    private func createAlbum(named title: String) async throws -> PHAssetCollection {
        var createdIdentifier: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            createdIdentifier = request.placeholderForCreatedAssetCollection.localIdentifier
        }
        guard let createdIdentifier,
              let collection = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [createdIdentifier],
                options: nil
              ).firstObject else {
            throw PhotoAlbumError.createdAlbumUnavailable
        }
        return collection
    }
}

private struct PhotoAlbumOption: Identifiable {
    let collection: PHAssetCollection
    let title: String
    let assetCount: Int
    let containsAsset: Bool

    var id: String { collection.localIdentifier }
}

private enum PhotoAlbumError: LocalizedError {
    case albumUnavailable
    case createdAlbumUnavailable

    var errorDescription: String? {
        switch self {
        case .albumUnavailable:
            return "このアルバムには写真を追加できません。"
        case .createdAlbumUnavailable:
            return "作成したアルバムを開けませんでした。もう一度お試しください。"
        }
    }
}
