import Foundation

@MainActor
final class PendingDeletionStore: ObservableObject {
    @Published private(set) var records: [PendingDeletionRecord]
    @Published private(set) var revision = 0

    private let defaults: UserDefaults
    private let key = "pendingDeletions.v1"
    private var identifierSet: Set<String>

    var assetIdentifiers: Set<String> {
        identifierSet
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedRecords: [PendingDeletionRecord]
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PendingDeletionRecord].self, from: data) {
            loadedRecords = decoded
        } else {
            loadedRecords = []
        }
        records = loadedRecords
        identifierSet = Set(loadedRecords.map(\.assetIdentifier))
    }

    func contains(assetIdentifier: String) -> Bool {
        identifierSet.contains(assetIdentifier)
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
        identifierSet.insert(assetIdentifier)
        revision &+= 1
        persist()
        return record
    }

    @discardableResult
    func remove(assetIdentifier: String) -> PendingDeletionRecord? {
        guard let index = records.firstIndex(where: { $0.assetIdentifier == assetIdentifier }) else {
            return nil
        }
        let record = records.remove(at: index)
        identifierSet.remove(assetIdentifier)
        revision &+= 1
        persist()
        return record
    }

    func removeAll() {
        guard !records.isEmpty else { return }
        records.removeAll()
        identifierSet.removeAll()
        revision &+= 1
        persist()
    }

    func remove(assetIdentifiers: Set<String>) {
        guard !assetIdentifiers.isEmpty else { return }
        let previousCount = records.count
        records.removeAll { assetIdentifiers.contains($0.assetIdentifier) }
        if records.count != previousCount {
            identifierSet.subtract(assetIdentifiers)
            revision &+= 1
            persist()
        }
    }

    @discardableResult
    func reconcile(validAssetIdentifiers: Set<String>) -> [PendingDeletionRecord] {
        let removed = records.filter { !validAssetIdentifiers.contains($0.assetIdentifier) }
        guard !removed.isEmpty else { return [] }
        records.removeAll { !validAssetIdentifiers.contains($0.assetIdentifier) }
        identifierSet.formIntersection(validAssetIdentifiers)
        revision &+= 1
        persist()
        return removed
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
