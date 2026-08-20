import SwiftUI

struct ActivityManagementView: View {
    @ObservedObject var timer: TimerViewModel
    @State private var newActivityName = ""
    @State private var editingActivityID: UUID?
    @State private var editingName = ""

    var body: some View {
        TabView {
            activityTab
                .tabItem { Label("活动管理", systemImage: "bookmark") }
            reviewTab
                .tabItem { Label("复盘", systemImage: "chart.bar") }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 470)
    }

    private var activityTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("活动管理")
                .font(.title2.weight(.semibold))
            Text("停用的活动不会出现在悬浮窗选择列表；有历史记录的删除会转为归档。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("新活动，例如：看论文", text: $newActivityName)
                Button("创建") {
                    if timer.createActivity(named: newActivityName) { newActivityName = "" }
                }
                .disabled(newActivityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            List(timer.activities) { activity in
                HStack(spacing: 10) {
                    Image(systemName: activity.status == .active ? "checkmark.circle.fill" : "pause.circle")
                        .foregroundStyle(activity.status == .active ? .green : .secondary)
                    if editingActivityID == activity.id {
                        TextField("活动名称", text: $editingName)
                            .onSubmit {
                                timer.renameActivity(activity.id, to: editingName)
                                editingActivityID = nil
                            }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                            Text(statusText(activity.status) + " · \(timer.recordCount(for: activity.id)) 条记录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if editingActivityID == activity.id {
                        Button("保存") {
                            timer.renameActivity(activity.id, to: editingName)
                            editingActivityID = nil
                        }
                    } else {
                        Button("改名") {
                            editingActivityID = activity.id
                            editingName = activity.name
                        }
                    }
                    Button(activity.status == .active ? "停用" : "启用") {
                        timer.setActivityStatus(activity.id, to: activity.status == .active ? .inactive : .active)
                    }
                    Button(timer.recordCount(for: activity.id) > 0 ? "归档" : "删除") {
                        timer.deleteOrArchiveActivity(activity.id)
                    }
                }
                .buttonStyle(.borderless)
            }
            .listStyle(.inset)
        }
    }

    private var reviewTab: some View {
        let records = timer.allRecords
        let daySummaries = FocusStatistics.daySummaries(records: records, endingAt: timer.now)
        let monthTotal = FocusStatistics.monthTotal(records: records, now: timer.now)
        let activitySummaries = FocusStatistics.activitySummaries(activities: timer.activities, records: records, now: timer.now)
        let activeHour = FocusStatistics.mostActiveHour(records: records, now: timer.now)

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("复盘")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 12) {
                    summaryCard("今日", value: duration(daySummaries.last?.focusedSeconds ?? 0))
                    summaryCard("本月", value: duration(monthTotal))
                    summaryCard("活跃时段", value: activeHour.map { String(format: "%02d:00", $0) } ?? "暂无")
                }

                GroupBox("最近 7 天") {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(daySummaries) { summary in
                            HStack {
                                Text(summary.day, format: .dateTime.weekday(.abbreviated).month().day())
                                Spacer()
                                Text(duration(summary.focusedSeconds)).monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("本月按活动") {
                    VStack(alignment: .leading, spacing: 7) {
                        if activitySummaries.isEmpty {
                            Text("还没有活动或记录")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(activitySummaries) { summary in
                            HStack {
                                Text(summary.activity.name)
                                Spacer()
                                Text(duration(summary.focusedSeconds)).monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("专注记录（可修正）") {
                    VStack(alignment: .leading, spacing: 8) {
                        if timer.records.isEmpty {
                            Text("还没有已结束的专注记录")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(timer.records.sorted { $0.endedAt > $1.endedAt }) { record in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(timer.activities.first(where: { $0.id == record.activityID })?.name ?? "已删除活动")
                                    Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("−5") { timer.adjustRecord(record.id, byMinutes: -5) }
                                    .disabled(record.focusedSeconds == 0)
                                Text(duration(record.focusedSeconds)).monospacedDigit()
                                Button("＋5") { timer.adjustRecord(record.id, byMinutes: 5) }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func summaryCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusText(_ status: ActivityStatus) -> String {
        switch status {
        case .active: "启用"
        case .inactive: "已停用"
        case .archived: "已归档"
        }
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds.rounded(.down)) / 60
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
