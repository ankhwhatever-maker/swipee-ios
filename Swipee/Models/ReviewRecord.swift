import Foundation

enum SwipeDecision: String, Codable { case trash, keep }

struct ReviewRecord: Codable, Equatable {
    let assetIdentifier: String
    let conditionKey: String
    let decision: SwipeDecision
    let reviewedAt: Date
}
