import Foundation

@MainActor
final class DuplicateReviewedStore: ObservableObject {
    @Published private(set) var groupIdentifiers: Set<String>

    private let defaults: UserDefaults
    private let key = "duplicateReviewedGroups.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        groupIdentifiers = Set(defaults.stringArray(forKey: key) ?? [])
    }

    func contains(_ groupIdentifier: String) -> Bool {
        groupIdentifiers.contains(groupIdentifier)
    }

    func markReviewed(_ groupIdentifier: String) {
        guard groupIdentifiers.insert(groupIdentifier).inserted else { return }
        persist()
    }

    func clear() {
        guard !groupIdentifiers.isEmpty else { return }
        groupIdentifiers.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(Array(groupIdentifiers).sorted(), forKey: key)
    }
}
