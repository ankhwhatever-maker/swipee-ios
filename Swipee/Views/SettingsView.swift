import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: CandidateSettingsStore
    @State private var showingFilters = false

    var body: some View {
        List {
            Section("写真の候補") {
                Button { showingFilters = true } label: { settingsRow("slider.horizontal.3", "表示する写真", detail: settings.value.summary, chevron: true) }.foregroundStyle(.primary)
            }
            Section("サポート") {
                NavigationLink { FAQView() } label: { settingsRow("questionmark.circle", "FAQ") }
                Link(destination: URL(string: "mailto:support.swipee@gmail.com")!) { settingsRow("envelope", "お問い合わせ", chevron: true) }.foregroundStyle(.primary)
                NavigationLink { LegalView(kind: .privacy) } label: { settingsRow("hand.raised", "プライバシーポリシー") }
                NavigationLink { LegalView(kind: .terms) } label: { settingsRow("doc.text", "利用規約") }
            }
            Section { Text("Swipee\nVersion 0.1.0").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center) }.listRowBackground(Color.clear)
        }
        .navigationTitle("設定")
        .sheet(isPresented: $showingFilters) { NavigationStack { PhotoFilterView() } }
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
