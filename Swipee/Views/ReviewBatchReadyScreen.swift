import SwiftUI

struct ReviewBatchReadyScreen: View {
    let itemCount: Int
    let onReview: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("\(itemCount)枚見ました", systemImage: "photo.stack")
        } description: {
            Text("削除する写真を確認して、今回の整理を終えましょう。")
        } actions: {
            Button("今回の\(itemCount)枚を確認", action: onReview)
                .buttonStyle(.borderedProminent)
        }
    }
}
