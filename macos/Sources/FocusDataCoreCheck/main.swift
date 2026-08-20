import FocusDataCore
import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!

func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var utcCalendar = Calendar(identifier: .gregorian)
    utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return utcCalendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour, minute: minute))!
}

let reading = Activity(name: "阅读", createdAt: date(20, 0))
let pausedRecords = [
    FocusRecord(activityID: reading.id, startedAt: date(20, 9), endedAt: date(20, 9, 20)),
    FocusRecord(activityID: reading.id, startedAt: date(20, 10, 10), endedAt: date(20, 10, 50)),
]
let buckets = FocusStatistics.hourlyBuckets(records: pausedRecords, on: date(20, 12), calendar: calendar)
precondition(buckets.count == 24)
precondition(buckets[9].focusedSeconds == 20 * 60)
precondition(buckets[10].focusedSeconds == 40 * 60)
precondition(buckets[11].focusedSeconds == 0)

let writing = Activity(name: "写作", createdAt: date(20, 0))
let overnight = FocusRecord(activityID: writing.id, startedAt: date(20, 23, 40), endedAt: date(21, 0, 20))
precondition(FocusStatistics.daySummary(records: [overnight], on: date(20, 12), calendar: calendar).focusedSeconds == 20 * 60)
precondition(FocusStatistics.daySummary(records: [overnight], on: date(21, 12), calendar: calendar).focusedSeconds == 20 * 60)
precondition(FocusStatistics.hourlyBuckets(records: [overnight], on: date(21, 12), calendar: calendar)[0].focusedSeconds == 20 * 60)

let legacyData = """
{"id":"00000000-0000-0000-0000-000000000001","activityID":"\(reading.id.uuidString)","startedAt":746582400,"endedAt":746582700,"focusedSeconds":3600}
""".data(using: .utf8)!
let legacyRecord = try JSONDecoder().decode(FocusRecord.self, from: legacyData)
precondition(legacyRecord.focusedSeconds == 300)

print("FocusDataCoreCheck: 8 checks passed")
