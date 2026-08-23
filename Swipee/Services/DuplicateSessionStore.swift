import Foundation

@MainActor
final class DuplicateSessionStore: ObservableObject {
    @Published private(set) var sessions: [String: [ReviewSessionItem]]

    private let defaults: UserDefaults
    private let key = "duplicateReviewSessions.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [ReviewSessionItem]].self, from: data) {
            sessions = decoded
        } else {
            sessions = [:]
        }
    }

    func items(for groupIdentifier: String) -> [ReviewSessionItem] {
        sessions[groupIdentifier] ?? []
    }

    func append(
        groupIdentifier: String,
        assetIdentifier: String,
        decision: SwipeDecision,
        previousFavoriteState: Bool? = nil,
        reviewedAt: Date = .now
    ) {
        var items = sessions[groupIdentifier] ?? []
        guard !items.contains(where: { $0.assetIdentifier == assetIdentifier }) else { return }
        items.append(
            ReviewSessionItem(
                assetIdentifier: assetIdentifier,
                sourceConditionKey: "duplicates|\(groupIdentifier)",
                decision: decision,
                originalDecision: decision,
                previousFavoriteState: previousFavoriteState,
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

    func updateDecision(
        groupIdentifier: String,
        assetIdentifier: String,
        decision: SwipeDecision,
        decisionBeforeDeletion: SwipeDecision? = nil
    ) {
        guard var items = sessions[groupIdentifier],
              let index = items.firstIndex(where: { $0.assetIdentifier == assetIdentifier }) else { return }
        items[index].decision = decision
        items[index].decisionBeforeDeletion = decision == .trash ? decisionBeforeDeletion : nil
        sessions[groupIdentifier] = items
        persist()
    }

    func clear(groupIdentifier: String) {
        guard sessions.removeValue(forKey: groupIdentifier) != nil else { return }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: key)
    }
}
