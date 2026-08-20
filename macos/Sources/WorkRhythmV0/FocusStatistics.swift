import Foundation

struct DayFocusSummary: Identifiable {
    let day: Date
    let focusedSeconds: TimeInterval
    var id: Date { day }
}

struct ActivityFocusSummary: Identifiable {
    let activity: Activity
    let focusedSeconds: TimeInterval
    var id: UUID { activity.id }
}

enum FocusStatistics {
    static func focusedSeconds(_ record: FocusRecord, during interval: DateInterval) -> TimeInterval {
        let recordInterval = DateInterval(start: record.startedAt, end: record.endedAt)
        guard let overlap = recordInterval.intersection(with: interval), recordInterval.duration > 0 else { return 0 }
        return record.focusedSeconds * overlap.duration / recordInterval.duration
    }

    static func daySummaries(records: [FocusRecord], endingAt now: Date, count: Int = 7, calendar: Calendar = .current) -> [DayFocusSummary] {
        (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            let interval = DateInterval(start: day, end: nextDay)
            return DayFocusSummary(day: day, focusedSeconds: records.reduce(0) { $0 + focusedSeconds($1, during: interval) })
        }
    }

    static func monthTotal(records: [FocusRecord], now: Date, calendar: Calendar = .current) -> TimeInterval {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return records.reduce(0) { $0 + focusedSeconds($1, during: interval) }
    }

    static func activitySummaries(activities: [Activity], records: [FocusRecord], now: Date, calendar: Calendar = .current) -> [ActivityFocusSummary] {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return [] }
        return activities.map { activity in
            ActivityFocusSummary(
                activity: activity,
                focusedSeconds: records.filter { $0.activityID == activity.id }.reduce(0) { $0 + focusedSeconds($1, during: interval) }
            )
        }
        .sorted { $0.focusedSeconds > $1.focusedSeconds }
    }

    static func mostActiveHour(records: [FocusRecord], now: Date, calendar: Calendar = .current) -> Int? {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return nil }
        let hours = (0..<24).map { hour -> (Int, TimeInterval) in
            let total = records.reduce(0) { partial, record in
                partial + focusedSecondsDuringHour(record, hour: hour, within: month, calendar: calendar)
            }
            return (hour, total)
        }
        return hours.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil }
    }

    private static func focusedSecondsDuringHour(_ record: FocusRecord, hour: Int, within month: DateInterval, calendar: Calendar) -> TimeInterval {
        let recordInterval = DateInterval(start: record.startedAt, end: record.endedAt)
        guard let bounded = recordInterval.intersection(with: month), recordInterval.duration > 0 else { return 0 }
        var cursor = calendar.dateInterval(of: .hour, for: bounded.start)?.start ?? bounded.start
        var result: TimeInterval = 0
        while cursor < bounded.end {
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            let hourInterval = DateInterval(start: cursor, end: next)
            if calendar.component(.hour, from: cursor) == hour,
               let overlap = bounded.intersection(with: hourInterval) {
                result += record.focusedSeconds * overlap.duration / recordInterval.duration
            }
            cursor = next
        }
        return result
    }
}
