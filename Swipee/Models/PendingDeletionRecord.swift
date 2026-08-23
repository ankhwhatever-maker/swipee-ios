import Foundation

enum PendingDeletionState: String, Codable {
    case pendingDeletion
}

struct PendingDeletionRecord: Codable, Equatable, Identifiable {
    let assetIdentifier: String
    let sourceConditionKey: String
    let queuedAt: Date
    let state: PendingDeletionState

    var id: String { assetIdentifier }

    init(assetIdentifier: String, sourceConditionKey: String, queuedAt: Date = .now) {
        self.assetIdentifier = assetIdentifier
        self.sourceConditionKey = sourceConditionKey
        self.queuedAt = queuedAt
        state = .pendingDeletion
    }
}
