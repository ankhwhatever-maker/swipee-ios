import Foundation

@MainActor
final class DuplicateSessionStore: ObservableObject {
    @Published private(set) var sessions: [String: [ReviewSessionItem]]
    @Published private(set) var completedCounts: [String: Int]

    private let defaults: UserDefaults
    private let key = "duplicateReviewSessions.v1"
    private let completedCountsKey = "duplicateReviewCompletedCounts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [ReviewSessionItem]].self, from: data) {
            sessions = decoded
        } else {
            sessions = [:]
        }
        if let data = defaults.data(forKey: completedCountsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            completedCounts = decoded
        } else {
            completedCounts = [:]
        }
    }

    func items(for groupIdentifier: String) -> [ReviewSessionItem] {
        sessions[groupIdentifier] ?? []
    }

    func completedCount(for groupIdentifier: String) -> Int {
        min(completedCounts[groupIdentifier] ?? 0, sessions[groupIdentifier]?.count ?? 0)
    }

    func markCurrentBatchCompleted(groupIdentifier: String, itemCount: Int) {
        let sessionCount = sessions[groupIdentifier]?.count ?? 0
        let nextCount = completedCount(for: groupIdentifier) + max(itemCount, 0)
        completedCounts[groupIdentifier] = min(nextCount, sessionCount)
        persist()
    }

    func append(
        groupIdentifier: String,
        assetIdentifier: String,
        decision: SwipeDecision,
        reviewedAt: Date = .now
    ) {
        var items = sessions[groupIdentifier] ?? []
        guard !items.contains(where: { $0.assetIdentifier == assetIdentifier }) else { return }
        items.append(
            ReviewSessionItem(
                assetIdentifier: assetIdentifier,
                sourceConditionKey: "duplicates|\(groupIdentifier)",
                decision: decision,
                reviewedAt: reviewedAt
            )
        )
        sessions[groupIdentifier] = items
        persist()
    }

    @discardableResult
    func removeLast(groupIdentifier: String) -> ReviewSessionItem? {
        guard var items = sessions[groupIdentifier], !items.isEmpty else { return nil }
        let item = items.removeLast()
        sessions[groupIdentifier] = items
        persist()
        return item
    }

    @discardableResult
    func remove(
        assetIdentifiers: Set<String>,
        groupIdentifier: String
    ) -> [ReviewSessionItem] {
        guard !assetIdentifiers.isEmpty,
              let currentItems = sessions[groupIdentifier] else { return [] }

        let removed = currentItems.filter { assetIdentifiers.contains($0.assetIdentifier) }
        guard !removed.isEmpty else { return [] }

        let completedCount = self.completedCount(for: groupIdentifier)
        let removedCompletedCount = currentItems.prefix(completedCount)
            .filter { assetIdentifiers.contains($0.assetIdentifier) }
            .count
        let remainingItems = currentItems.filter {
            !assetIdentifiers.contains($0.assetIdentifier)
        }
        sessions[groupIdentifier] = remainingItems
        completedCounts[groupIdentifier] = min(
            max(completedCount - removedCompletedCount, 0),
            remainingItems.count
        )
        persist()
        return removed
    }

    func updateDecision(
        groupIdentifier: String,
        assetIdentifier: String,
        decision: SwipeDecision
    ) {
        guard var items = sessions[groupIdentifier],
              let index = items.firstIndex(where: { $0.assetIdentifier == assetIdentifier }) else { return }
        items[index].decision = decision
        sessions[groupIdentifier] = items
        persist()
    }

    func clear(groupIdentifier: String) {
        let removedSession = sessions.removeValue(forKey: groupIdentifier) != nil
        let removedCount = completedCounts.removeValue(forKey: groupIdentifier) != nil
        guard removedSession || removedCount else { return }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: key)
        if let completedData = try? JSONEncoder().encode(completedCounts) {
            defaults.set(completedData, forKey: completedCountsKey)
        }
    }
}
