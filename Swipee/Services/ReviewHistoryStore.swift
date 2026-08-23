import Foundation

@MainActor
final class ReviewHistoryStore: ObservableObject {
    @Published private(set) var records: [ReviewRecord]
    private let defaults: UserDefaults
    private let key = "reviewHistory.v1"
    private var reviewedKeys: Set<ReviewKey>

    private struct ReviewKey: Hashable {
        let assetIdentifier: String
        let conditionKey: String
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loadedRecords: [ReviewRecord]
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([ReviewRecord].self, from: data) {
            loadedRecords = decoded
        } else {
            loadedRecords = []
        }
        records = loadedRecords
        reviewedKeys = Set(loadedRecords.map {
            ReviewKey(assetIdentifier: $0.assetIdentifier, conditionKey: $0.conditionKey)
        })
    }

    func hasReviewed(assetIdentifier: String, conditionKey: String) -> Bool {
        reviewedKeys.contains(ReviewKey(assetIdentifier: assetIdentifier, conditionKey: conditionKey))
    }

    func assetIdentifiers(for conditionKey: String) -> Set<String> {
        Set(reviewedKeys.lazy
            .filter { $0.conditionKey == conditionKey }
            .map(\.assetIdentifier))
    }

    func record(assetIdentifier: String, conditionKey: String, decision: SwipeDecision) {
        records.removeAll { $0.assetIdentifier == assetIdentifier && $0.conditionKey == conditionKey }
        records.append(ReviewRecord(assetIdentifier: assetIdentifier, conditionKey: conditionKey, decision: decision, reviewedAt: .now))
        reviewedKeys.insert(ReviewKey(assetIdentifier: assetIdentifier, conditionKey: conditionKey))
        persist()
    }

    @discardableResult
    func remove(assetIdentifier: String, conditionKey: String) -> ReviewRecord? {
        guard let index = records.firstIndex(where: {
            $0.assetIdentifier == assetIdentifier && $0.conditionKey == conditionKey
        }) else {
            return nil
        }
        let record = records.remove(at: index)
        reviewedKeys.remove(ReviewKey(assetIdentifier: assetIdentifier, conditionKey: conditionKey))
        persist()
        return record
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
