import Foundation

public enum TimerStatus: String, Codable, Equatable {
    case idle, running, paused, breakDue, resting
}

public struct TimerEngine: Codable {
    private static let defaultFocusLength: TimeInterval = 50 * 60
    public private(set) var status: TimerStatus = .idle
    private(set) var startedAt: Date?
    private(set) var pausedAt: Date?
    private(set) var breakStartedAt: Date?
    private(set) var completedFocus: TimeInterval = 0
    private(set) var pausedFocus: TimeInterval = 0
    private(set) var cycleFocus: TimeInterval = 0
    private(set) var focusLimit: TimeInterval = TimerEngine.defaultFocusLength

    public init() {}

    public mutating func start(at now: Date) {
        guard status == .idle else { return }
        startedAt = now
        pausedAt = nil
        pausedFocus = 0
        status = .running
    }

    public mutating func pause(at now: Date) {
        guard status == .running else { return }
        pausedAt = now
        status = .paused
    }

    public mutating func resume(at now: Date) {
        guard (status == .paused || status == .breakDue), let pausedAt else { return }
        pausedFocus += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
        status = .running
    }

    public mutating func stop(at now: Date) {
        guard status == .running || status == .paused else { return }
        let focus = activeFocus(at: now)
        completedFocus += focus
        cycleFocus += focus
        startedAt = nil
        pausedAt = nil
        pausedFocus = 0
        status = .idle
    }

    public mutating func handleSleep(at now: Date) {
        pause(at: now)
    }

    public mutating func resolveBreakDue(at now: Date) {
        guard status == .running, remainingBreakSeconds(at: now) == 0 else { return }
        let cappedFocus = max(0, focusLimit - cycleFocus)
        let rawFocus = rawActiveFocus(at: now)
        pausedAt = now.addingTimeInterval(-max(0, rawFocus - cappedFocus))
        status = .breakDue
    }

    public mutating func beginBreak(at now: Date) {
        guard status == .breakDue else { return }
        commitCurrentFocus(at: now)
        breakStartedAt = now
        status = .resting
    }

    public mutating func deferBreak(at now: Date, by interval: TimeInterval = 10 * 60) {
        guard status == .breakDue else { return }
        focusLimit += interval
        resume(at: now)
    }

    public mutating func skipBreak(at now: Date) {
        guard status == .breakDue else { return }
        commitCurrentFocus(at: now)
        prepareNextFocusCycle()
    }

    public mutating func resolveRestCompletion(at now: Date, breakLength: TimeInterval = 5 * 60) {
        guard status == .resting, remainingRestSeconds(at: now, breakLength: breakLength) == 0 else { return }
        prepareNextFocusCycle()
    }

    public func activeFocus(at now: Date) -> TimeInterval {
        min(rawActiveFocus(at: now), max(0, focusLimit - cycleFocus))
    }

    private func rawActiveFocus(at now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        let end = pausedAt ?? now
        return max(0, end.timeIntervalSince(startedAt) - pausedFocus)
    }

    /// Timer-engine accumulation. Calendar-day totals must be derived from immutable focus records.
    public func cumulativeFocus(at now: Date) -> TimeInterval {
        completedFocus + activeFocus(at: now)
    }

    public func remainingBreakSeconds(at now: Date) -> TimeInterval {
        max(0, focusLimit - cycleFocus - activeFocus(at: now))
    }

    public func remainingRestSeconds(at now: Date, breakLength: TimeInterval = 5 * 60) -> TimeInterval {
        guard let breakStartedAt else { return breakLength }
        return max(0, breakLength - now.timeIntervalSince(breakStartedAt))
    }

    private mutating func commitCurrentFocus(at now: Date) {
        let focus = activeFocus(at: now)
        completedFocus += focus
        cycleFocus += focus
        startedAt = nil
        pausedAt = nil
        pausedFocus = 0
    }

    private mutating func prepareNextFocusCycle() {
        cycleFocus = 0
        focusLimit = TimerEngine.defaultFocusLength
        breakStartedAt = nil
        status = .idle
    }

    private enum CodingKeys: String, CodingKey {
        case status, startedAt, pausedAt, breakStartedAt, completedFocus, pausedFocus, cycleFocus, focusLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decodeIfPresent(TimerStatus.self, forKey: .status) ?? .idle
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        breakStartedAt = try container.decodeIfPresent(Date.self, forKey: .breakStartedAt)
        completedFocus = try container.decodeIfPresent(TimeInterval.self, forKey: .completedFocus) ?? 0
        pausedFocus = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedFocus) ?? 0
        cycleFocus = try container.decodeIfPresent(TimeInterval.self, forKey: .cycleFocus) ?? 0
        focusLimit = try container.decodeIfPresent(TimeInterval.self, forKey: .focusLimit) ?? TimerEngine.defaultFocusLength
    }
}
