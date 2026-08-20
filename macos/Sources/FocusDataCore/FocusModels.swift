import Foundation

public enum ActivityStatus: String, Codable, Equatable, Sendable {
    case active, inactive, archived
}

public struct Activity: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var status: ActivityStatus

    public init(name: String, createdAt: Date = Date()) {
        id = UUID()
        self.name = name
        self.createdAt = createdAt
        status = .active
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, status
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        status = try container.decodeIfPresent(ActivityStatus.self, forKey: .status) ?? .active
    }
}

/// An immutable interval created only when the timer closes a focused period.
public struct FocusRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let activityID: UUID
    public let startedAt: Date
    public let endedAt: Date

    public var focusedSeconds: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    public init(id: UUID = UUID(), activityID: UUID, startedAt: Date, endedAt: Date) {
        self.id = id
        self.activityID = activityID
        self.startedAt = startedAt
        self.endedAt = max(endedAt, startedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, activityID, startedAt, endedAt
        // Retained only so old local debug records can be decoded. It is never used.
        case focusedSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        activityID = try container.decode(UUID.self, forKey: .activityID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        let decodedEnd = try container.decode(Date.self, forKey: .endedAt)
        endedAt = max(decodedEnd, startedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(activityID, forKey: .activityID)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(endedAt, forKey: .endedAt)
    }
}

public struct HourFocusBucket: Identifiable, Equatable, Sendable {
    public struct ActivityValue: Identifiable, Equatable, Sendable {
        public let activityID: UUID
        public let focusedSeconds: TimeInterval
        public var id: UUID { activityID }

        public init(activityID: UUID, focusedSeconds: TimeInterval) {
            self.activityID = activityID
            self.focusedSeconds = focusedSeconds
        }
    }

    public let start: Date
    public let end: Date
    public let values: [ActivityValue]
    public var id: Date { start }
    public var focusedSeconds: TimeInterval { values.reduce(0) { $0 + $1.focusedSeconds } }

    public init(start: Date, end: Date, values: [ActivityValue]) {
        self.start = start
        self.end = end
        self.values = values
    }
}

public struct DayFocusSummary: Identifiable, Equatable, Sendable {
    public let day: Date
    public let focusedSeconds: TimeInterval
    public var id: Date { day }

    public init(day: Date, focusedSeconds: TimeInterval) {
        self.day = day
        self.focusedSeconds = focusedSeconds
    }
}

public struct ActivityFocusSummary: Identifiable, Equatable, Sendable {
    public let activity: Activity
    public let focusedSeconds: TimeInterval
    public var id: UUID { activity.id }

    public init(activity: Activity, focusedSeconds: TimeInterval) {
        self.activity = activity
        self.focusedSeconds = focusedSeconds
    }
}
