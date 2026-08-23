import Foundation

struct DuplicatePhotoGroup: Codable, Equatable, Hashable, Identifiable, Sendable {
    let assetIdentifiers: [String]

    var id: String { assetIdentifiers.sorted().joined(separator: "|") }
    var representativeIdentifier: String { assetIdentifiers.first ?? "" }
    var count: Int { assetIdentifiers.count }
}
