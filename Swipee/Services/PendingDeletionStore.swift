import Foundation

@MainActor
final class PendingDeletionStore: ObservableObject {
    @Published private(set) var records: [PendingDeletionRecord]

    private let defaults: UserDefaults
    private let key = "pendingDeletions.v1"

    var assetIdentifiers: Set<String> {
        Set(records.map(\.assetIdentifier))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PendingDeletionRecord].self, from: data) {
            records = decoded
        } else {
            records = []
        }
    }

    func contains(assetIdentifier: String) -> Bool {
        records.contains { $0.assetIdentifier == assetIdentifier }
    }

    @discardableResult
    func enqueue(
        assetIdentifier: String,
        sourceConditionKey: String,
        queuedAt: Date = .now
    ) -> PendingDeletionRecord {
        if let existing = records.first(where: { $0.assetIdentifier == assetIdentifier }) {
            return existing
        }
        let record = PendingDeletionRecord(
            assetIdentifier: assetIdentifier,
            sourceConditionKey: sourceConditionKey,
            queuedAt: queuedAt
        )
        records.append(record)
        persist()
        return record
    }

    @discardableResult
    func remove(assetIdentifier: String) -> PendingDeletionRecord? {
        guard let index = records.firstIndex(where: { $0.assetIdentifier == assetIdentifier }) else {
            return nil
        }
        let record = records.remove(at: index)
        persist()
        return record
    }

    func removeAll() {
        guard !records.isEmpty else { return }
        records.removeAll()
        persist()
    }

    func remove(assetIdentifiers: Set<String>) {
        guard !assetIdentifiers.isEmpty else { return }
        let previousCount = records.count
        records.removeAll { assetIdentifiers.contains($0.assetIdentifier) }
        if records.count != previousCount { persist() }
    }

    @discardableResult
    func reconcile(validAssetIdentifiers: Set<String>) -> [PendingDeletionRecord] {
        let removed = records.filter { !validAssetIdentifiers.contains($0.assetIdentifier) }
        guard !removed.isEmpty else { return [] }
        records.removeAll { !validAssetIdentifiers.contains($0.assetIdentifier) }
        persist()
        return removed
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
