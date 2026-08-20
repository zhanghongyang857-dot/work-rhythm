import Charts
import FocusDataCore
import SwiftUI

struct ActivityManagementView: View {
    @ObservedObject var timer: TimerViewModel
    @State private var newActivityName = ""
    @State private var editingActivityID: UUID?
    @State private var editingName = ""
    @State private var reviewMode: ReviewMode = .today
    @State private var reviewDate = Date()
    @State private var trendDays = 7

    private enum ReviewMode: String, CaseIterable, Identifiable {
        case today = "今日"
        case trend = "趋势"
        var id: Self { self }
    }

    var body: some View {
        TabView {
            reviewTab
                .tabItem { Label("复盘", systemImage: "chart.bar.xaxis") }
            activityTab
                .tabItem { Label("活动", systemImage: "square.stack.3d.up") }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 620)
    }

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("活动")
                    .font(.title2.weight(.semibold))
                Text("启用的活动会出现在浮窗中；归档会保留已有专注记录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("新活动，例如：看论文", text: $newActivityName)
                    .textFieldStyle(.roundedBorder)
                Button("创建") {
                    if timer.createActivity(named: newActivityName) { newActivityName = "" }
                }
                .disabled(newActivityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            List(timer.activities) { activity in
                HStack(spacing: 12) {
                    Image(systemName: activity.status == .active ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(activity.status == .active ? WorkRhythmStyle.focus : .secondary)
                    if editingActivityID == activity.id {
                        TextField("活动名称", text: $editingName)
                            .onSubmit { saveRename(activity) }
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activity.name)
                            Text(statusText(activity.status) + " · \(timer.recordCount(for: activity.id)) 段专注")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if editingActivityID == activity.id {
                        Button("保存") { saveRename(activity) }
                    } else {
                        Menu {
                            Button("改名") {
                                editingActivityID = activity.id
                                editingName = activity.name
                            }
                            Button(activity.status == .active ? "停用" : "启用") {
                                timer.setActivityStatus(activity.id, to: activity.status == .active ? .inactive : .active)
                            }
                            Divider()
                            Button(timer.recordCount(for: activity.id) > 0 ? "归档" : "删除", role: .destructive) {
                                timer.deleteOrArchiveActivity(activity.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
                .buttonStyle(.borderless)
            }
            .listStyle(.inset)
        }
    }

    private var reviewTab: some View {
        let records = timer.allRecords
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                reviewHeader
                Picker("复盘范围", selection: $reviewMode) {
                    ForEach(ReviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                switch reviewMode {
                case .today:
                    TodayReview(records: records, activities: timer.activities, date: reviewDate)
                case .trend:
                    TrendReview(records: records, activities: timer.activities, endingAt: reviewDate, days: $trendDays)
                }
            }
            .padding(.bottom, 10)
        }
    }

    private var reviewHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("复盘")
                    .font(.title2.weight(.semibold))
                Text("只记录真实发生的专注时间。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { moveReviewDate(by: -1) } label: { Image(systemName: "chevron.left") }
                DatePicker("日期", selection: $reviewDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                Button { moveReviewDate(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(Calendar.current.startOfDay(for: reviewDate) >= Calendar.current.startOfDay(for: timer.now))
            }
            .buttonStyle(.borderless)
        }
    }

    private func moveReviewDate(by days: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: days, to: reviewDate) else { return }
        reviewDate = min(date, timer.now)
    }

    private func saveRename(_ activity: Activity) {
        timer.renameActivity(activity.id, to: editingName)
        editingActivityID = nil
    }

    private func statusText(_ status: ActivityStatus) -> String {
        switch status {
        case .active: "启用"
        case .inactive: "已停用"
        case .archived: "已归档"
        }
    }
}

private struct TodayReview: View {
    let records: [FocusRecord]
    let activities: [Activity]
    let date: Date

    private var calendar: Calendar { .current }
    private var interval: DateInterval { FocusStatistics.dayInterval(for: date, calendar: calendar)! }
    private var summary: DayFocusSummary { FocusStatistics.daySummary(records: records, on: date, calendar: calendar) }
    private var buckets: [HourFocusBucket] { FocusStatistics.hourlyBuckets(records: records, on: date, calendar: calendar) }
    private var activitySummaries: [ActivityFocusSummary] {
        FocusStatistics.activitySummaries(activities: activities, records: records, during: interval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                MetricCard(title: "有效专注", value: duration(summary.focusedSeconds))
                MetricCard(title: "专注段数", value: "\(records.filter { FocusStatistics.focusedSeconds($0, during: interval) > 0 }.count)")
                MetricCard(title: "最长连续", value: duration(FocusStatistics.longestFocus(records: records, during: interval)))
                MetricCard(title: "首次开始", value: FocusStatistics.firstFocusStart(records: records, during: interval).map(time) ?? "—")
            }

            ReviewSurface(title: "一日节律", subtitle: "每柱代表该小时的有效专注分钟数") {
                HourlyFocusChart(buckets: buckets, activities: activities, day: interval)
                    .frame(height: 220)
            }

            ReviewSurface(title: "按活动投入", subtitle: nil) {
                ActivityDistribution(summaries: activitySummaries, total: summary.focusedSeconds)
            }
        }
    }
}

private struct TrendReview: View {
    let records: [FocusRecord]
    let activities: [Activity]
    let endingAt: Date
    @Binding var days: Int

    private var calendar: Calendar { .current }
    private var summaries: [DayFocusSummary] {
        FocusStatistics.daySummaries(records: records, endingAt: endingAt, count: days, calendar: calendar)
    }
    private var monthInterval: DateInterval { calendar.dateInterval(of: .month, for: endingAt)! }
    private var monthActivities: [ActivityFocusSummary] {
        FocusStatistics.activitySummaries(activities: activities, records: records, during: monthInterval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("最近")
                    .foregroundStyle(.secondary)
                Picker("范围", selection: $days) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                Spacer()
                MetricCard(title: "最活跃时段", value: FocusStatistics.mostActiveHour(records: records, endingAt: endingAt, calendar: calendar).map { String(format: "%02d:00", $0) } ?? "—")
                    .frame(width: 145)
            }

            ReviewSurface(title: "每日投入", subtitle: "有效专注时长") {
                Chart(summaries) { item in
                    BarMark(
                        x: .value("日期", item.day, unit: .day),
                        y: .value("分钟", item.focusedSeconds / 60)
                    )
                    .foregroundStyle(WorkRhythmStyle.focus)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: days == 7 ? 7 : 6)) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .frame(height: 190)
            }

            ReviewSurface(title: "本月按活动", subtitle: nil) {
                ActivityDistribution(summaries: monthActivities, total: FocusStatistics.total(records: records, during: monthInterval))
            }
        }
    }
}

private struct HourlyFocusChart: View {
    let buckets: [HourFocusBucket]
    let activities: [Activity]
    let day: DateInterval
    @State private var selectedHour: Date?

    private var calendar: Calendar { .current }
    private var selectedBucket: HourFocusBucket? {
        guard let selectedHour else { return nil }
        return buckets.first { calendar.isDate($0.start, equalTo: selectedHour, toGranularity: .hour) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(buckets) { bucket in
                    ForEach(bucket.values) { value in
                        BarMark(
                            x: .value("时段", bucket.start, unit: .hour),
                            y: .value("分钟", value.focusedSeconds / 60)
                        )
                        .foregroundStyle(color(for: value.activityID))
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    }
                }
                RuleMark(y: .value("满", 60))
                    .foregroundStyle(.primary.opacity(0.10))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            }
            .chartXScale(domain: day.start...day.end)
            .chartYScale(domain: 0...60)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 30, 60]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.primary.opacity(0.08))
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)m") }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let origin = geometry[proxy.plotAreaFrame].origin
                                guard let date: Date = proxy.value(atX: location.x - origin.x),
                                      let hour = calendar.dateInterval(of: .hour, for: date)?.start else { return }
                                selectedHour = hour
                            case .ended:
                                selectedHour = nil
                            }
                        }
                }
            }

            if let selectedBucket, selectedBucket.focusedSeconds > 0 {
                Text(hourDetail(selectedBucket))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("将指针停在柱图上查看该小时的专注。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func hourDetail(_ bucket: HourFocusBucket) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let activityDetail = bucket.values.map { value in
            let name = activities.first(where: { $0.id == value.activityID })?.name ?? "已归档活动"
            return "\(name) \(duration(value.focusedSeconds))"
        }
        return "\(formatter.string(from: bucket.start))–\(formatter.string(from: bucket.end)) · " + activityDetail.joined(separator: " · ")
    }

    private func color(for activityID: UUID) -> Color {
        let palette: [Color] = [WorkRhythmStyle.focus, Color(red: 0.37, green: 0.48, blue: 0.44), Color(red: 0.52, green: 0.42, blue: 0.32), Color(red: 0.43, green: 0.39, blue: 0.51), Color(red: 0.45, green: 0.46, blue: 0.36)]
        let index = activities.firstIndex(where: { $0.id == activityID }) ?? 0
        return palette[index % palette.count]
    }
}

private struct ActivityDistribution: View {
    let summaries: [ActivityFocusSummary]
    let total: TimeInterval

    var body: some View {
        if summaries.isEmpty {
            Text("开始一次专注后，这里会显示时间投向。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            VStack(spacing: 12) {
                ForEach(Array(summaries.prefix(5).enumerated()), id: \.element.id) { index, summary in
                    HStack(spacing: 10) {
                        Circle().fill(color(for: index)).frame(width: 7, height: 7)
                        Text(summary.activity.name)
                        GeometryReader { geometry in
                            Capsule()
                                .fill(.primary.opacity(0.07))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(color(for: index))
                                        .frame(width: geometry.size.width * (total > 0 ? summary.focusedSeconds / total : 0))
                                }
                        }
                        .frame(height: 6)
                        Text(duration(summary.focusedSeconds))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(for index: Int) -> Color {
        [WorkRhythmStyle.focus, Color(red: 0.37, green: 0.48, blue: 0.44), Color(red: 0.52, green: 0.42, blue: 0.32), Color(red: 0.43, green: 0.39, blue: 0.51), Color(red: 0.45, green: 0.46, blue: 0.36)][index % 5]
    }
}

private struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct ReviewSurface<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(18)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private func duration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds.rounded(.down)) / 60
    return String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

private func time(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}
