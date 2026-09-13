@preconcurrency import Photos
import SwiftUI

struct AutoEnhancementView: View {
    let asset: PHAsset
    let onSaved: () -> Void

    @State private var originalImage: UIImage?
    @State private var enhancedImage: UIImage?
    @State private var showsOriginal = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveErrorMessage: String?

    var body: some View {
        Group {
            if let originalImage, let enhancedImage {
                preview(originalImage: originalImage, enhancedImage: enhancedImage)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("自動補正できませんでした", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("もう一度試す") { load() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("写真を補正しています…")
                        .font(.headline)
                }
            }
        }
        .navigationTitle("自動補正")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPreview() }
        .alert("保存できませんでした", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "")
        }
    }

    private func preview(originalImage: UIImage, enhancedImage: UIImage) -> some View {
        VStack(spacing: 18) {
            Image(uiImage: showsOriginal ? originalImage : enhancedImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.swipeeBorder, lineWidth: 1)
                }

            Picker("表示", selection: $showsOriginal) {
                Text("補正後").tag(false)
                Text("オリジナル").tag(true)
            }
            .pickerStyle(.segmented)

            Button(action: save) {
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
        originalImage = nil
        enhancedImage = nil
        errorMessage = nil
        Task { await loadPreview() }
    }

    private func loadPreview() async {
        do {
            let preview = try await AutoEnhancementService.preview(asset: asset)
            guard !Task.isCancelled else { return }
            guard let loadedOriginalImage = preview.originalImage,
                  let loadedEnhancedImage = preview.enhancedImage else {
                throw AutoEnhancementViewError.previewUnavailable
            }
            originalImage = loadedOriginalImage
            enhancedImage = loadedEnhancedImage
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await AutoEnhancementService.saveEnhancedPhoto(sourceAsset: asset)
                onSaved()
            } catch {
                saveErrorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private enum AutoEnhancementViewError: LocalizedError {
    case previewUnavailable

    var errorDescription: String? {
        "自動補正した写真を表示できませんでした。"
    }
}
