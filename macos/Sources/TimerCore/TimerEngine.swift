import Foundation

public enum TimerStatus: Equatable {
    case idle, running, paused, breakDue
}

public struct TimerEngine {
    public private(set) var status: TimerStatus = .idle
    private(set) var startedAt: Date?
    private(set) var pausedAt: Date?
    private(set) var completedFocus: TimeInterval = 0
    private(set) var pausedFocus: TimeInterval = 0
    private(set) var cycleFocus: TimeInterval = 0

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
        guard status == .paused, let pausedAt else { return }
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

    public mutating func resolveBreakDue(at now: Date, cycleLength: TimeInterval = 50 * 60) {
        guard status == .running, remainingBreakSeconds(at: now, cycleLength: cycleLength) == 0 else { return }
        status = .breakDue
    }

    public func activeFocus(at now: Date, cycleLength: TimeInterval = 50 * 60) -> TimeInterval {
        guard let startedAt else { return 0 }
        let end = pausedAt ?? now
        let elapsed = max(0, end.timeIntervalSince(startedAt) - pausedFocus)
        return min(elapsed, max(0, cycleLength - cycleFocus))
    }

    public func todayFocus(at now: Date) -> TimeInterval {
        completedFocus + activeFocus(at: now)
    }

    public func remainingBreakSeconds(at now: Date, cycleLength: TimeInterval = 50 * 60) -> TimeInterval {
        max(0, cycleLength - cycleFocus - activeFocus(at: now, cycleLength: cycleLength))
    }
}
