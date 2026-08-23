# Swipee for iOS

SwiftUI と PhotoKit で実装した、写真を少しずつ手放すための iOS ネイティブアプリです。

## 開く

1. Xcode で `Swipee.xcodeproj` を開く
2. Signing & Capabilities で Team と Bundle Identifier を設定する
3. 写真の入った実機を選び Run する

シミュレータでも写真を追加すれば画面確認できますが、削除・お気に入り・限定アクセスを含む最終確認は実機で行ってください。

## 構成

- `Swipee/App`: エントリーポイントと3タブ（整理・重複・設定）
- `Swipee/Models`: 候補条件、メディア種別、確認履歴、重複グループ
- `Swipee/Services`: PhotoKit、端末内永続化、類似写真解析
- `Swipee/Views`: スワイプ、10枚ごとの確認・一括削除、重複候補、設定画面
- `SwipeeTests`: 候補条件、確認履歴、削除候補、セッション状態のユニットテスト

写真そのものをネットワークへ送る処理、アカウント、バックエンド、広告、StoreKit は含みません。
