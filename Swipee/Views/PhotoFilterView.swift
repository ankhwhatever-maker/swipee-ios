import SwiftUI

struct PhotoFilterView: View {
    @EnvironmentObject private var settings: CandidateSettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("期間") {
                VStack(spacing: 20) {
                    Text(settings.value.period.displayLabel).font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    Slider(value: Binding(get: { Double(settings.value.period.rawValue) }, set: { settings.setPeriod(CandidatePeriod(rawValue: Int($0.rounded())) ?? .all) }), in: 0...4, step: 1)
                        .tint(.primary)
                        .accessibilityLabel("表示する期間")
                        .accessibilityValue(settings.value.period.displayLabel)
                    HStack {
                        ForEach(CandidatePeriod.allCases) { period in
                            Text(period.shortLabel).font(.caption2).fontWeight(settings.value.period == period ? .bold : .regular).foregroundStyle(settings.value.period == period ? Color.primary : Color.secondary).frame(maxWidth: .infinity)
                        }
                    }
                }.padding(.vertical, 8)
            }
            Section { ForEach(CandidateMediaKind.allCases) { kind in mediaRow(kind) } } header: { Text("種類") } footer: { Text("複数選択できます。設定はこの端末にすぐ保存されます。") }
            Section("お気に入り") {
                Toggle(
                    "お気に入りも表示",
                    isOn: Binding(
                        get: { settings.value.includesFavorites },
                        set: { settings.setIncludesFavorites($0) }
                    )
                )
            }
        }
        .navigationTitle("表示する写真")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("完了")
            }
        }
    }

    private func mediaRow(_ kind: CandidateMediaKind) -> some View {
        Button { settings.toggle(kind) } label: {
            HStack(spacing: 14) {
                Image(systemName: kind.icon).frame(width: 26).foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) { Text(kind.label).foregroundStyle(.primary); if let detail = kind.detail { Text(detail).font(.caption).foregroundStyle(.secondary) } }
                Spacer()
                Image(systemName: settings.value.mediaKinds.contains(kind) ? "checkmark.circle.fill" : "circle").foregroundStyle(settings.value.mediaKinds.contains(kind) ? Color.primary : Color.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(settings.value.mediaKinds.contains(kind) ? "選択中" : "未選択")
    }
}
