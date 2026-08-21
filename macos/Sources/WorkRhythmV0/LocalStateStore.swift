import Foundation
import FocusDataCore
import TimerCore

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

/// The on-disk format version is intentionally independent from the app version.
/// Future versions must back up and migrate older schemas before writing a new one.
private struct PersistedStateEnvelope: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let state: PersistedAppState
}

enum LocalStateStoreError: LocalizedError {
    case unreadable(Error)
    case invalidFormat
    case unsupportedSchema(Int)
    case unwritable(Error)
    case noStateToBackUp

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "无法读取已有的本地数据。为避免覆盖它，应用不会继续自动保存。"
        case .invalidFormat:
            "本地数据格式无法识别。为避免覆盖它，应用不会继续自动保存。"
        case .unsupportedSchema(let version):
            "本地数据版本 v\(version) 尚不受此版本应用支持。"
        case .unwritable:
            "无法写入本地数据。请检查磁盘空间和文件夹权限。"
        case .noStateToBackUp:
            "还没有可备份的数据。"
        }
    }
}

struct LocalStateStore {
    private let fileManager = FileManager.default

    private var storageDirectory: URL {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(storageDirectoryName, isDirectory: true)
        return directory
    }

    private var storageDirectoryName: String {
#if DEBUG
        "com.zhanghongyang.workrhythm.debug"
#else
        "com.zhanghongyang.workrhythm"
#endif
    }

    private var stateURL: URL {
        storageDirectory.appendingPathComponent("state.json")
    }

    func load() throws -> PersistedAppState? {
        guard fileManager.fileExists(atPath: stateURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: stateURL)
        } catch {
            throw LocalStateStoreError.unreadable(error)
        }

        let envelope: PersistedStateEnvelope
        do {
            envelope = try JSONDecoder().decode(PersistedStateEnvelope.self, from: data)
        } catch {
            throw LocalStateStoreError.invalidFormat
        }
        guard envelope.schemaVersion == PersistedStateEnvelope.currentSchemaVersion else {
            throw LocalStateStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        return envelope.state
    }

    func save(_ state: PersistedAppState) throws {
        do {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let envelope = PersistedStateEnvelope(
                schemaVersion: PersistedStateEnvelope.currentSchemaVersion,
                state: state
            )
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            throw LocalStateStoreError.unwritable(error)
        }
    }

    func createBackup() throws -> URL {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            throw LocalStateStoreError.noStateToBackUp
        }
        let backupDirectory = storageDirectory.appendingPathComponent("backups", isDirectory: true)
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = backupDirectory.appendingPathComponent("WorkRhythm-backup-\(timestamp).json")
        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: stateURL, to: backupURL)
            return backupURL
        } catch {
            throw LocalStateStoreError.unwritable(error)
        }
    }
}
