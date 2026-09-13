import Foundation

@MainActor
final class ReviewSessionStore: ObservableObject {
    static let targetCount = 10

    @Published private(set) var items: [ReviewSessionItem]
    @Published private(set) var totalDeletedCount: Int

    private let defaults: UserDefaults
    private let itemsKey = "reviewSession.items.v1"
    private let totalDeletedKey = "reviewSession.totalDeleted.v1"

    var isComplete: Bool { items.count >= Self.targetCount }
    var progressText: String { "\(min(items.count, Self.targetCount))/\(Self.targetCount)" }
    var deletionCount: Int { items.filter { $0.decision == .trash }.count }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: itemsKey),
           let decoded = try? JSONDecoder().decode([ReviewSessionItem].self, from: data) {
            items = decoded
        } else {
            items = []
        }
        totalDeletedCount = defaults.integer(forKey: totalDeletedKey)
    }

    func append(
        assetIdentifier: String,
        sourceConditionKey: String,
        decision: SwipeDecision,
        reviewedAt: Date = .now
    ) {
        guard !items.contains(where: { $0.assetIdentifier == assetIdentifier }) else { return }
        items.append(
            ReviewSessionItem(
                assetIdentifier: assetIdentifier,
                sourceConditionKey: sourceConditionKey,
                decision: decision,
                reviewedAt: reviewedAt
            )
        )
        persistItems()
    }

    @discardableResult
    func removeLast() -> ReviewSessionItem? {
        guard !items.isEmpty else { return nil }
        let item = items.removeLast()
        persistItems()
        return item
    }

    @discardableResult
    func remove(assetIdentifier: String) -> ReviewSessionItem? {
        guard let index = items.firstIndex(where: { $0.assetIdentifier == assetIdentifier }) else {
            return nil
        }
        let item = items.remove(at: index)
        persistItems()
        return item
    }

    func updateDecision(
        assetIdentifier: String,
        decision: SwipeDecision
    ) {
        guard let index = items.firstIndex(where: { $0.assetIdentifier == assetIdentifier }) else { return }
        items[index].decision = decision
        persistItems()
    }

    func importPendingRecords(_ records: [PendingDeletionRecord]) {
        var changed = false
        for record in records where !items.contains(where: { $0.assetIdentifier == record.assetIdentifier }) {
            items.append(
                ReviewSessionItem(
                    assetIdentifier: record.assetIdentifier,
                    sourceConditionKey: record.sourceConditionKey,
                    decision: .trash,
                    reviewedAt: record.queuedAt
                )
            )
            changed = true
        }
        if changed { persistItems() }
    }

    func finish(deletedCount: Int) {
        recordDeleted(count: deletedCount)
        items.removeAll()
        persistItems()
    }

    func recordDeleted(count: Int) {
        guard count > 0 else { return }
        totalDeletedCount += count
        defaults.set(totalDeletedCount, forKey: totalDeletedKey)
    }

    private func persistItems() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: itemsKey)
    }
}
