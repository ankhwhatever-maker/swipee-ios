import Foundation

struct ReviewSessionItem: Codable, Equatable, Identifiable {
    let assetIdentifier: String
    let sourceConditionKey: String
    var decision: SwipeDecision
    var decisionBeforeDeletion: SwipeDecision? = nil
    var originalDecision: SwipeDecision? = nil
    var previousFavoriteState: Bool? = nil
    let reviewedAt: Date

    var id: String { assetIdentifier }

    var decisionRestoredAfterRemovingDeletion: SwipeDecision {
        decisionBeforeDeletion ?? .keep
    }
}
