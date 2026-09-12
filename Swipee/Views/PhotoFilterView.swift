import SwiftUI

struct PhotoFilterView: View {
    @EnvironmentObject private var settings: CandidateSettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CandidateSettings?

    private var selection: CandidateSettings {
        draft ?? settings.value
    }

    var body: some View {
        Form {
            Section("期間") {
                VStack(spacing: 20) {
                    Text(selection.period.displayLabel).font(.largeTitle.bold()).frame(maxWidth: .infinity, alignment: .leading)
                    Slider(value: Binding(get: { Double(selection.period.rawValue) }, set: { setPeriod(CandidatePeriod(rawValue: Int($0.rounded())) ?? .all) }), in: 0...4, step: 1)
                        .tint(.primary)
                        .accessibilityLabel("表示する期間")
                        .accessibilityValue(selection.period.displayLabel)
                    HStack {
                        ForEach(CandidatePeriod.allCases) { period in
                            Text(period.shortLabel).font(.caption2).fontWeight(selection.period == period ? .bold : .regular).foregroundStyle(selection.period == period ? Color.primary : Color.secondary).frame(maxWidth: .infinity)
                        }
                    }
                }.padding(.vertical, 8)
            }
            Section { ForEach(CandidateMediaKind.allCases) { kind in mediaRow(kind) } } header: { Text("種類") } footer: { Text("複数選択できます。チェックを押すと設定が保存されます。") }
            Section("お気に入り") {
                favoriteRow
            }
        }
        .navigationTitle("表示する写真")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button { applyAndDismiss() } label: {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("完了")
            }
        }
        .onAppear {
            if draft == nil { draft = settings.value }
        }
    }

    private func mediaRow(_ kind: CandidateMediaKind) -> some View {
        Button { toggle(kind) } label: {
            HStack(spacing: 14) {
                Image(systemName: kind.icon).frame(width: 26).foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 2) { Text(kind.label).foregroundStyle(.primary); if let detail = kind.detail { Text(detail).font(.caption).foregroundStyle(.secondary) } }
                Spacer()
                Image(systemName: selection.mediaKinds.contains(kind) ? "checkmark.circle.fill" : "circle").foregroundStyle(selection.mediaKinds.contains(kind) ? Color.primary : Color.secondary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityValue(selection.mediaKinds.contains(kind) ? "選択中" : "未選択")
    }

    private var favoriteRow: some View {
        Button {
            var updated = selection
            updated.includesFavorites.toggle()
            draft = updated
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "heart")
                    .frame(width: 26)
                    .foregroundStyle(.primary)
                Text("お気に入り")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: selection.includesFavorites ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.includesFavorites ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("お気に入りの写真を表示")
        .accessibilityValue(selection.includesFavorites ? "選択中" : "未選択")
    }

    private func setPeriod(_ period: CandidatePeriod) {
        var updated = selection
        updated.period = period
        draft = updated
    }

    private func toggle(_ kind: CandidateMediaKind) {
        var updated = selection
        if updated.mediaKinds.contains(kind) {
            updated.mediaKinds.remove(kind)
        } else {
            updated.mediaKinds.insert(kind)
        }
        draft = updated
    }

    private func applyAndDismiss() {
        settings.set(selection)
        dismiss()
    }
}
