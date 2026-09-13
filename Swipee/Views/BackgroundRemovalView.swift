@preconcurrency import Photos
import SwiftUI

struct BackgroundRemovalView: View {
    let asset: PHAsset
    let onSaved: () -> Void

    @State private var result: BackgroundRemovalResult?
    @State private var originalImage: UIImage?
    @State private var cutoutImage: UIImage?
    @State private var showsOriginal = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveErrorMessage: String?

    var body: some View {
        Group {
            if let result, let originalImage, let cutoutImage {
                preview(result: result, originalImage: originalImage, cutoutImage: cutoutImage)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("背景を削除できませんでした", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("もう一度試す") { load() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("被写体を確認しています…")
                        .font(.headline)
                    Text("写真によっては少し時間がかかります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("背景を削除")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadResult() }
        .alert("保存できませんでした", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func preview(
        result: BackgroundRemovalResult,
        originalImage: UIImage,
        cutoutImage: UIImage
    ) -> some View {
        VStack(spacing: 18) {
            ZStack {
                CheckerboardBackground()
                Image(uiImage: showsOriginal ? originalImage : cutoutImage)
                    .resizable()
                    .scaledToFit()
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.swipeeBorder, lineWidth: 1)
            }
            .frame(maxHeight: .infinity)

            Picker("表示", selection: $showsOriginal) {
                Text("背景削除後").tag(false)
                Text("オリジナル").tag(true)
            }
            .pickerStyle(.segmented)

            Button {
                save(result)
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("新しい写真として保存", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
        }
        .padding(20)
    }

    private func load() {
        result = nil
        originalImage = nil
        cutoutImage = nil
        errorMessage = nil
        Task { await loadResult() }
    }

    private func loadResult() async {
        do {
            let loadedResult = try await BackgroundRemovalService.process(asset: asset)
            guard !Task.isCancelled else { return }
            guard let loadedOriginalImage = loadedResult.originalImage,
                  let loadedCutoutImage = loadedResult.cutoutImage else {
                throw BackgroundRemovalViewError.previewUnavailable
            }
            result = loadedResult
            originalImage = loadedOriginalImage
            cutoutImage = loadedCutoutImage
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func save(_ result: BackgroundRemovalResult) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await BackgroundRemovalService.save(result, sourceAsset: asset)
                onSaved()
            } catch {
                saveErrorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private enum BackgroundRemovalViewError: LocalizedError {
    case previewUnavailable

    var errorDescription: String? {
        "背景を削除した写真を表示できませんでした。"
    }
}

private struct CheckerboardBackground: View {
    private let squareSize: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for column in 0..<columns {
                    let color = (row + column).isMultiple(of: 2)
                        ? Color.white
                        : Color(white: 0.88)
                    context.fill(
                        Path(CGRect(
                            x: CGFloat(column) * squareSize,
                            y: CGFloat(row) * squareSize,
                            width: squareSize,
                            height: squareSize
                        )),
                        with: .color(color)
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}
