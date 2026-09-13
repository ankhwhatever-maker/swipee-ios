import SwiftUI

struct ReviewBatchReadyScreen: View {
    let itemCount: Int
    var onBack: (() -> Void)? = nil
    let onReview: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("\(itemCount)枚見ました", systemImage: "photo.stack")
        } description: {
            Text("削除する写真を確認して、今回の整理を終えましょう。")
        } actions: {
            Button("削除対象を確認", action: onReview)
                .buttonStyle(.borderedProminent)
        }
        .overlay(alignment: .topLeading) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel("重複候補へ戻る")
                .padding(.top, 8)
                .padding(.leading, 4)
            }
        }
    }
}
