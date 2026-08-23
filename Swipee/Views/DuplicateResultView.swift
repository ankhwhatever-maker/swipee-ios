import SwiftUI

struct DuplicateResultView: View {
    let result: DuplicateGroupResult
    let onFinished: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.075, green: 0.067, blue: 0.063).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: onFinished) {
                        Image(systemName: "xmark").font(.title.bold()).frame(width: 52, height: 52)
                    }
                    .foregroundStyle(.white)
                    .accessibilityLabel("閉じる")
                }
                Spacer(minLength: 36)
                Text("重複").font(.title2.bold())
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(result.deletedCount)")
                        .font(.system(size: 104, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.65)
                    Text("枚").font(.system(size: 44, weight: .bold, design: .rounded))
                }
                .padding(.top, 12)
                Text(result.deletedCount == 0 ? "削除はありません" : "削除しました").font(.title2.bold())
                HStack(spacing: 14) {
                    resultCard(count: result.keptCount, title: "キープ", icon: "checkmark", color: .swipeeKeep)
                    resultCard(count: result.deletedCount, title: "削除", icon: "trash", color: .swipeeDelete)
                }
                .padding(.top, 48)
                Text("累計 \(result.totalDeletedCount)枚を削除").font(.title3.bold()).padding(.top, 34)
                if result.deletedCount > 0 {
                    Text("削除した写真は、写真アプリの「最近削除した項目」から復元できます。")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 10)
                }
                Spacer(minLength: 36)
                Button(action: onFinished) {
                    Text("重複候補へ戻る").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(.bottom, 10)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.dark)
    }

    private func resultCard(count: Int, title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Text("\(count)").font(.system(size: 54, weight: .bold, design: .rounded))
            Label(title, systemImage: icon).font(.headline)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
