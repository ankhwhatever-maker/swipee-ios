import SwiftUI

struct PhotoFilterView: View {
    @EnvironmentObject private var settings: CandidateSettingsStore
    @EnvironmentObject private var history: ReviewHistoryStore
    @EnvironmentObject private var session: ReviewSessionStore
    @EnvironmentObject private var duplicateReviewed: DuplicateReviewedStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CandidateSettings?
    @State private var showingReviewedResetConfirmation = false

    private var selection: CandidateSettings {
        draft ?? settings.value
    }

    var body: some View {
        Form {
            Section("期間") {
                Picker("期間の指定方法", selection: dateModeBinding) {
                    ForEach(CandidateDateMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if selection.dateMode == .recent {
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
                } else {
                    DatePicker(
                        "開始日",
                        selection: customStartDateBinding,
                        in: ...customEndDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "終了日",
                        selection: customEndDateBinding,
                        in: customStartDate...,
                        displayedComponents: .date
                    )
                }
            }
            Section { ForEach(CandidateMediaKind.allCases) { kind in mediaRow(kind) } } header: { Text("種類") } footer: { Text("複数選択できます。チェックを押すと設定が保存されます。") }
            Section("お気に入り") {
                favoriteRow
            }
            Section {
                Button("整理済みの写真を再表示") {
                    showingReviewedResetConfirmation = true
                }
                .disabled(!hasResettableReviewedItems)
            } header: {
                Text("整理済みの写真")
            } footer: {
                Text("整理済みの写真と重複候補を、もう一度表示します。")
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
        .alert(
            "整理済みの写真をもう一度表示しますか？",
            isPresented: $showingReviewedResetConfirmation
        ) {
            Button("キャンセル", role: .cancel) {}
            Button("再表示") {
                history.clearKept(excluding: currentSessionKeptIdentifiers)
                duplicateReviewed.clear()
            }
        } message: {
            Text("整理済みの写真と重複候補を、もう一度表示します。")
        }
    }

    private var currentSessionKeptIdentifiers: Set<String> {
        Set(session.items.lazy
            .filter { $0.decision == .keep }
            .map(\.assetIdentifier))
    }

    private var resettableKeptCount: Int {
        history.keptAssetIdentifiers.subtracting(currentSessionKeptIdentifiers).count
    }

    private var hasResettableReviewedItems: Bool {
        resettableKeptCount > 0 || !duplicateReviewed.groupIdentifiers.isEmpty
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
                Text("お気に入りを表示する")
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: selection.includesFavorites ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.includesFavorites ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("お気に入りを表示する")
        .accessibilityValue(selection.includesFavorites ? "選択中" : "未選択")
    }

    private var dateModeBinding: Binding<CandidateDateMode> {
        Binding(
            get: { selection.dateMode },
            set: { mode in
                var updated = selection
                updated.dateMode = mode
                if mode == .custom {
                    let calendar = Calendar.current
                    let end = calendar.startOfDay(for: .now)
                    updated.customEndDate = updated.customEndDate ?? end
                    updated.customStartDate = updated.customStartDate
                        ?? calendar.date(byAdding: .month, value: -1, to: end)
                }
                draft = updated
            }
        )
    }

    private var customStartDate: Date {
        selection.customStartDate
            ?? Calendar.current.date(byAdding: .month, value: -1, to: customEndDate)
            ?? customEndDate
    }

    private var customEndDate: Date {
        selection.customEndDate ?? Calendar.current.startOfDay(for: .now)
    }

    private var customStartDateBinding: Binding<Date> {
        Binding(
            get: { customStartDate },
            set: { date in
                var updated = selection
                updated.customStartDate = Calendar.current.startOfDay(for: date)
                draft = updated
            }
        )
    }

    private var customEndDateBinding: Binding<Date> {
        Binding(
            get: { customEndDate },
            set: { date in
                var updated = selection
                updated.customEndDate = Calendar.current.startOfDay(for: date)
                draft = updated
            }
        )
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
