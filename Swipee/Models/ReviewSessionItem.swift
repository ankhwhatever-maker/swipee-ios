import Foundation

struct ReviewSessionItem: Codable, Equatable, Identifiable {
    let assetIdentifier: String
    let sourceConditionKey: String
    var decision: SwipeDecision
    let reviewedAt: Date

    var id: String { assetIdentifier }
}
