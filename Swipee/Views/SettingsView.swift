import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: CandidateSettingsStore
    @State private var showingFilters = false
    @State private var message: SettingsMessage?

    var body: some View {
        List {
            Section("写真の候補") {
                Button { showingFilters = true } label: { settingsRow("slider.horizontal.3", "表示する写真", detail: settings.value.summary, chevron: true) }.foregroundStyle(.primary)
            }
            Section("Swipee") {
                Button { message = .premium } label: { settingsRow("sparkles", "プレミアム", detail: "準備中", chevron: true) }.foregroundStyle(.primary)
                Button { message = .restore } label: { settingsRow("arrow.clockwise", "購入を復元") }.foregroundStyle(.primary)
            }
            Section("サポート") {
                NavigationLink { FAQView() } label: { settingsRow("questionmark.circle", "FAQ") }
                Link(destination: URL(string: "mailto:support@example.com")!) { settingsRow("envelope", "お問い合わせ", chevron: true) }.foregroundStyle(.primary)
                NavigationLink { LegalView(kind: .privacy) } label: { settingsRow("hand.raised", "プライバシーポリシー") }
                NavigationLink { LegalView(kind: .terms) } label: { settingsRow("doc.text", "利用規約") }
            }
            Section { Text("Swipee\nVersion 0.1.0").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center) }.listRowBackground(Color.clear)
        }
        .navigationTitle("設定")
        .sheet(isPresented: $showingFilters) { NavigationStack { PhotoFilterView() } }
        .alert(item: $message) { item in Alert(title: Text(item.title), message: Text(item.body), dismissButton: .default(Text("OK"))) }
    }

    private func settingsRow(_ icon: String, _ title: String, detail: String? = nil, chevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.primary).frame(width: 28)
            Text(title)
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            if chevron { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary) }
        }
    }
}

private enum SettingsMessage: String, Identifiable {
    case premium, restore
    var id: String { rawValue }
    var title: String { self == .premium ? "プレミアム" : "購入を復元" }
    var body: String { self == .premium ? "プレミアム機能は今後のアップデートで提供予定です。" : "このバージョンには購入機能がありません。" }
}
