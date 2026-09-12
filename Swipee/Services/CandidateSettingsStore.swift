import Foundation

@MainActor
final class CandidateSettingsStore: ObservableObject {
    @Published private(set) var value: CandidateSettings
    private let defaults: UserDefaults
    private let key = "candidateSettings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(CandidateSettings.self, from: data) {
            value = decoded
        } else {
            value = CandidateSettings()
        }
    }

    func set(_ settings: CandidateSettings) {
        guard value != settings else { return }
        value = settings
        save()
    }

    func setPeriod(_ period: CandidatePeriod) { value.period = period; save() }
    func setIncludesFavorites(_ includesFavorites: Bool) {
        value.includesFavorites = includesFavorites
        save()
    }
    func toggle(_ kind: CandidateMediaKind) {
        if value.mediaKinds.contains(kind) { value.mediaKinds.remove(kind) } else { value.mediaKinds.insert(kind) }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
