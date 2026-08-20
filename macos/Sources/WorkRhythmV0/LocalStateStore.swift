import Foundation
import TimerCore

enum ActivityStatus: String, Codable, Equatable {
    case active, inactive, archived
}

struct Activity: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var status: ActivityStatus

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
        status = .active
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decodeIfPresent(ActivityStatus.self, forKey: .status) ?? .active
    }
}

struct FocusRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let activityID: UUID
    let startedAt: Date
    let endedAt: Date
    var focusedSeconds: TimeInterval
}

struct ActiveFocusSegment: Codable, Equatable {
    let activityID: UUID
    let startedAt: Date
    let focusAtStart: TimeInterval
}

struct PersistedAppState: Codable {
    let activities: [Activity]
    let selectedActivityID: UUID?
    let engine: TimerEngine
    let records: [FocusRecord]
    let activeSegment: ActiveFocusSegment?
    let savedAt: Date
}

struct LocalStateStore {
    private let fileManager = FileManager.default

    private var stateFilename: String {
#if DEBUG
        "v4-debug-state.json"
#else
        "state.json"
#endif
    }

    private var stateURL: URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WorkRhythm", isDirectory: true)
        return directory.appendingPathComponent(stateFilename)
    }

    func load() -> PersistedAppState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(PersistedAppState.self, from: data)
    }

    func save(_ state: PersistedAppState) {
        let directory = stateURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    func reset() {
        guard fileManager.fileExists(atPath: stateURL.path) else { return }
        try? fileManager.removeItem(at: stateURL)
    }
}
