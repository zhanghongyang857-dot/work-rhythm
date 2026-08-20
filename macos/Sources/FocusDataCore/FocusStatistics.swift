import Foundation

public enum FocusStatistics {
    public static func focusedSeconds(_ record: FocusRecord, during interval: DateInterval) -> TimeInterval {
        let recordInterval = DateInterval(start: record.startedAt, end: record.endedAt)
        guard let overlap = recordInterval.intersection(with: interval) else { return 0 }
        return overlap.duration
    }

    public static func total(records: [FocusRecord], during interval: DateInterval) -> TimeInterval {
        records.reduce(0) { $0 + focusedSeconds($1, during: interval) }
    }

    public static func dayInterval(for date: Date, calendar: Calendar = .current) -> DateInterval? {
        calendar.dateInterval(of: .day, for: date)
    }

    public static func daySummary(records: [FocusRecord], on date: Date, calendar: Calendar = .current) -> DayFocusSummary {
        let day = calendar.startOfDay(for: date)
        let focusedTotal = dayInterval(for: date, calendar: calendar).map { total(records: records, during: $0) } ?? 0
        return DayFocusSummary(day: day, focusedSeconds: focusedTotal)
    }

    public static func hourlyBuckets(records: [FocusRecord], on date: Date, calendar: Calendar = .current) -> [HourFocusBucket] {
        let day = calendar.startOfDay(for: date)
        return (0..<24).compactMap { hour in
            guard let start = calendar.date(byAdding: .hour, value: hour, to: day),
                  let end = calendar.date(byAdding: .hour, value: 1, to: start) else { return nil }
            let interval = DateInterval(start: start, end: end)
            var totals: [UUID: TimeInterval] = [:]
            for record in records {
                let seconds = focusedSeconds(record, during: interval)
                if seconds > 0 { totals[record.activityID, default: 0] += seconds }
            }
            let values = totals.map { HourFocusBucket.ActivityValue(activityID: $0.key, focusedSeconds: $0.value) }
                .sorted { $0.focusedSeconds > $1.focusedSeconds }
            return HourFocusBucket(start: start, end: end, values: values)
        }
    }

    public static func daySummaries(records: [FocusRecord], endingAt now: Date, count: Int = 7, calendar: Calendar = .current) -> [DayFocusSummary] {
        (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)) else { return nil }
            return daySummary(records: records, on: day, calendar: calendar)
        }
    }

    public static func periodInterval(endingAt now: Date, days: Int, calendar: Calendar = .current) -> DateInterval? {
        guard let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: now)),
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        return DateInterval(start: start, end: end)
    }

    public static func monthTotal(records: [FocusRecord], now: Date, calendar: Calendar = .current) -> TimeInterval {
        guard let interval = calendar.dateInterval(of: .month, for: now) else { return 0 }
        return total(records: records, during: interval)
    }

    public static func activitySummaries(activities: [Activity], records: [FocusRecord], during interval: DateInterval) -> [ActivityFocusSummary] {
        activities.map { activity in
            ActivityFocusSummary(
                activity: activity,
                focusedSeconds: total(records: records.filter { $0.activityID == activity.id }, during: interval)
            )
        }
        .filter { $0.focusedSeconds > 0 }
        .sorted { $0.focusedSeconds > $1.focusedSeconds }
    }

    public static func mostActiveHour(records: [FocusRecord], endingAt now: Date, days: Int = 30, calendar: Calendar = .current) -> Int? {
        guard let period = periodInterval(endingAt: now, days: days, calendar: calendar) else { return nil }
        let hours = (0..<24).map { hour -> (Int, TimeInterval) in
            let total = records.reduce(0) { partial, record in
                partial + focusedSecondsDuringHour(record, hour: hour, within: period, calendar: calendar)
            }
            return (hour, total)
        }
        return hours.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil }
    }

    public static func longestFocus(records: [FocusRecord], during interval: DateInterval) -> TimeInterval {
        records.map { focusedSeconds($0, during: interval) }.max() ?? 0
    }

    public static func firstFocusStart(records: [FocusRecord], during interval: DateInterval) -> Date? {
        records.compactMap { record -> Date? in
            let recordInterval = DateInterval(start: record.startedAt, end: record.endedAt)
            return recordInterval.intersection(with: interval)?.start
        }
        .min()
    }

    private static func focusedSecondsDuringHour(_ record: FocusRecord, hour: Int, within period: DateInterval, calendar: Calendar) -> TimeInterval {
        let recordInterval = DateInterval(start: record.startedAt, end: record.endedAt)
        guard let bounded = recordInterval.intersection(with: period) else { return 0 }
        var cursor = calendar.dateInterval(of: .hour, for: bounded.start)?.start ?? bounded.start
        var result: TimeInterval = 0
        while cursor < bounded.end {
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            let hourInterval = DateInterval(start: cursor, end: next)
            if calendar.component(.hour, from: cursor) == hour,
               let overlap = bounded.intersection(with: hourInterval) {
                result += overlap.duration
            }
            cursor = next
        }
        return result
    }
}
