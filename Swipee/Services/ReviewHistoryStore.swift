import Foundation

@MainActor
final class ReviewHistoryStore: ObservableObject {
    @Published private(set) var records: [ReviewRecord]
    @Published private(set) var keptHistoryRevision = 0
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

    var keptAssetIdentifiers: Set<String> {
        Set(records.lazy
            .filter { $0.decision == .keep }
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

    func clearKept(excluding excludedIdentifiers: Set<String> = []) {
        let previousCount = records.count
        records.removeAll {
            $0.decision == .keep && !excludedIdentifiers.contains($0.assetIdentifier)
        }
        guard records.count != previousCount else { return }
        reviewedKeys = Set(records.map {
            ReviewKey(assetIdentifier: $0.assetIdentifier, conditionKey: $0.conditionKey)
        })
        keptHistoryRevision &+= 1
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}
