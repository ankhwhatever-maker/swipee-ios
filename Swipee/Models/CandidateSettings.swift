import Foundation
import Photos

enum CandidatePeriod: Int, Codable, CaseIterable, Identifiable, Sendable {
    case oneMonth, threeMonths, oneYear, threeYears, all

    var id: Int { rawValue }
    var shortLabel: String { ["1ヶ月", "3ヶ月", "1年", "3年", "すべて"][rawValue] }
    var displayLabel: String { self == .all ? "すべての期間" : "過去\(shortLabel)" }
    var monthCount: Int? { [1, 3, 12, 36, nil][rawValue] }

    func startDate(now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let monthCount else { return nil }
        return calendar.date(byAdding: .month, value: -monthCount, to: now)
    }
}

enum CandidateMediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo, video, screenshot
    var id: String { rawValue }
    var label: String {
        switch self { case .photo: "写真"; case .video: "動画"; case .screenshot: "スクリーンショット" }
    }
    var detail: String? { self == .photo ? "スクリーンショットを除く・Live Photoを含む" : nil }
    var icon: String {
        switch self { case .photo: "photo"; case .video: "video"; case .screenshot: "iphone" }
    }
}

struct CandidateSettings: Codable, Equatable, Sendable {
    var period: CandidatePeriod = .all
    var mediaKinds: Set<CandidateMediaKind> = [.photo, .screenshot]

    var conditionKey: String {
        let kinds = mediaKinds.map(\.rawValue).sorted().joined(separator: ",")
        return "v1|unreviewed|\(period.rawValue)|\(kinds)"
    }

    var summary: String {
        let kinds = CandidateMediaKind.allCases.filter(mediaKinds.contains).map(\.label).joined(separator: "、")
        return "\(period == .all ? "すべて" : period.shortLabel)・\(kinds.isEmpty ? "種類なし" : kinds)"
    }

    func includes(_ asset: PHAsset) -> Bool {
        if let start = period.startDate(), let creationDate = asset.creationDate, creationDate < start { return false }
        switch asset.mediaType {
        case .video: return mediaKinds.contains(.video)
        case .image:
            return asset.mediaSubtypes.contains(.photoScreenshot)
                ? mediaKinds.contains(.screenshot)
                : mediaKinds.contains(.photo)
        default: return false
        }
    }
}
