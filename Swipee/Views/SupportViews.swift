import SwiftUI

struct FAQView: View {
    private let items = [
        ("写真は外部へ送信されますか？", "いいえ。写真はPhotoKitを通して端末内でのみ処理し、外部サーバーへ送信しません。"),
        ("削除した写真は戻せますか？", "Swipee内にUndoはありません。一定期間は写真アプリの「最近削除した項目」から復元できます。"),
        ("同じ写真がまた表示されることはありますか？", "キープした写真は、表示条件を変更しても候補から除外されます。フィルター画面からキープ履歴をリセットすると、もう一度表示できます。"),
        ("限定アクセスでも使えますか？", "はい。アクセスを許可した写真だけが候補になります。")
    ]
    var body: some View {
        List(items, id: \.0) { item in DisclosureGroup(item.0) { Text(item.1).foregroundStyle(.secondary).padding(.vertical, 6) } }
            .navigationTitle("FAQ")
    }
}

enum LegalKind { case privacy, terms }

struct LegalView: View {
    let kind: LegalKind
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 8) { Text(section.0).font(.headline); Text(section.1).foregroundStyle(.secondary).lineSpacing(5) }
                }
                Text("最終更新日：2026年8月21日").font(.caption).foregroundStyle(.tertiary)
            }.padding()
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
    private var title: String { kind == .privacy ? "プライバシーポリシー" : "利用規約" }
    private var sections: [(String, String)] {
        if kind == .privacy {
            return [("写真データ", "Swipeeは写真ライブラリへのアクセス許可を得た範囲で写真を表示・整理します。写真データを外部サーバーへ送信しません。"), ("端末内のデータ", "候補条件と確認履歴を端末内に保存します。アカウントやクラウド同期は使用しません。"), ("お問い合わせ", "本ポリシーに関するお問い合わせは、設定画面のお問い合わせ先へご連絡ください。")]
        }
        return [("サービス", "Swipeeは、ユーザー自身の写真ライブラリを任意のペースで整理するためのアプリです。"), ("写真の変更", "削除やお気に入りの操作はiOSの確認と権限に基づいて写真ライブラリへ反映されます。削除した写真の管理は写真アプリで行ってください。"), ("免責", "重要な写真は事前にバックアップし、内容を確認したうえで操作してください。")]
    }
}
