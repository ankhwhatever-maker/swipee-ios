import Foundation

@MainActor
final class ReviewHistoryStore: ObservableObject {
    @Published private(set) var records: [ReviewRecord]
    private let defaults: UserDefaults
    private let key = "reviewHistory.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([ReviewRecord].self, from: data) {
            records = decoded
        } else { records = [] }
    }

    func hasReviewed(assetIdentifier: String, conditionKey: String) -> Bool {
        records.contains { $0.assetIdentifier == assetIdentifier && $0.conditionKey == conditionKey }
    }

    func record(assetIdentifier: String, conditionKey: String, decision: SwipeDecision) {
        records.removeAll { $0.assetIdentifier == assetIdentifier && $0.conditionKey == conditionKey }
        records.append(ReviewRecord(assetIdentifier: assetIdentifier, conditionKey: conditionKey, decision: decision, reviewedAt: .now))
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
        persist()
        return record
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
