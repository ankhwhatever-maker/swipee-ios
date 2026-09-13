import SwiftUI
import UIKit

struct PhotoAccessRequiredView: View {
    var body: some View {
        ContentUnavailableView {
            Label("写真へのアクセスが必要です", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("設定アプリでSwipeeの写真アクセスを許可してください。")
        } actions: {
            Button("設定を開く", action: openSettings)
                .buttonStyle(.borderedProminent)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
