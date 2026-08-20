import Foundation
import TimerCore

struct Activity: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let createdAt: Date

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = Date()
    }
}

struct FocusRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let activityID: UUID
    let startedAt: Date
    let endedAt: Date
    let focusedSeconds: TimeInterval
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
        "v3-debug-state.json"
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
