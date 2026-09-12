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

enum CandidateDateMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case recent
    case custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: "最近の写真"
        case .custom: "日付を指定"
        }
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
    var includesFavorites = true
    var dateMode: CandidateDateMode = .recent
    var customStartDate: Date?
    var customEndDate: Date?

    private enum CodingKeys: String, CodingKey {
        case period
        case mediaKinds
        case includesFavorites
        case dateMode
        case customStartDate
        case customEndDate
    }

    init(
        period: CandidatePeriod = .all,
        mediaKinds: Set<CandidateMediaKind> = [.photo, .screenshot],
        includesFavorites: Bool = true,
        dateMode: CandidateDateMode = .recent,
        customStartDate: Date? = nil,
        customEndDate: Date? = nil
    ) {
        self.period = period
        self.mediaKinds = mediaKinds
        self.includesFavorites = includesFavorites
        self.dateMode = dateMode
        self.customStartDate = customStartDate
        self.customEndDate = customEndDate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        period = try container.decodeIfPresent(CandidatePeriod.self, forKey: .period) ?? .all
        mediaKinds = try container.decodeIfPresent(Set<CandidateMediaKind>.self, forKey: .mediaKinds)
            ?? [.photo, .screenshot]
        includesFavorites = try container.decodeIfPresent(Bool.self, forKey: .includesFavorites) ?? true
        dateMode = try container.decodeIfPresent(CandidateDateMode.self, forKey: .dateMode) ?? .recent
        customStartDate = try container.decodeIfPresent(Date.self, forKey: .customStartDate)
        customEndDate = try container.decodeIfPresent(Date.self, forKey: .customEndDate)
    }

    var conditionKey: String {
        let kinds = mediaKinds.map(\.rawValue).sorted().joined(separator: ",")
        let favoriteFilter = includesFavorites ? "" : "|no-favorites"
        let dateFilter: String
        switch dateMode {
        case .recent:
            dateFilter = "\(period.rawValue)"
        case .custom:
            dateFilter = "custom|\(dayKey(customStartDate))|\(dayKey(customEndDate))"
        }
        return "v1|unreviewed|\(dateFilter)|\(kinds)\(favoriteFilter)"
    }

    var summary: String {
        let kinds = CandidateMediaKind.allCases.filter(mediaKinds.contains).map(\.label).joined(separator: "、")
        let favorites = includesFavorites ? "" : "・お気に入りを除外"
        let dateSummary: String
        switch dateMode {
        case .recent:
            dateSummary = period == .all ? "すべて" : period.shortLabel
        case .custom:
            dateSummary = "\(formattedDay(customStartDate))〜\(formattedDay(customEndDate))"
        }
        return "\(dateSummary)・\(kinds.isEmpty ? "種類なし" : kinds)\(favorites)"
    }

    func includes(_ asset: PHAsset) -> Bool {
        let bounds = dateBounds()
        if let start = bounds.start {
            guard let creationDate = asset.creationDate, creationDate >= start else { return false }
        }
        if let end = bounds.endExclusive {
            guard let creationDate = asset.creationDate, creationDate < end else { return false }
        }
        if !includesFavorites, asset.isFavorite { return false }
        switch asset.mediaType {
        case .video: return mediaKinds.contains(.video)
        case .image:
            return asset.mediaSubtypes.contains(.photoScreenshot)
                ? mediaKinds.contains(.screenshot)
                : mediaKinds.contains(.photo)
        default: return false
        }
    }

    func dateBounds(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> (start: Date?, endExclusive: Date?) {
        switch dateMode {
        case .recent:
            return (period.startDate(now: now, calendar: calendar), nil)
        case .custom:
            let start = customStartDate.map { calendar.startOfDay(for: $0) }
            let endDay = customEndDate.map { calendar.startOfDay(for: $0) }
            let endExclusive = endDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
            return (start, endExclusive)
        }
    }

    private func dayKey(_ date: Date?) -> String {
        guard let date else { return "none" }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func formattedDay(_ date: Date?) -> String {
        guard let date else { return "未指定" }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
