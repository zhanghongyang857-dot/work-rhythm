import AppKit
import Combine
import FocusDataCore
import SwiftUI
import TimerCore

@main
struct WorkRhythmV0App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Work Rhythm", systemImage: "timer") {
            Button("显示浮窗") {
                appDelegate.showPanel()
            }
            Button("隐藏浮窗") {
                appDelegate.hidePanel()
            }
            Button("管理活动与复盘") {
                openWindow(id: "activity-management")
            }
            Divider()
            Button("退出测试") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)

        Window("活动管理与复盘", id: "activity-management") {
            ActivityManagementView(timer: appDelegate.timer)
        }
        .defaultSize(width: 800, height: 660)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?
    let timer = TimerViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        panelController = FloatingPanelController(timer: timer)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        showPanel()
    }

    @objc private func handleWillSleep(_ notification: Notification) {
        panelController?.handleSleep()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.prepareForTermination()
    }

    func showPanel() {
        panelController?.show()
    }

    func hidePanel() {
        panelController?.hide()
    }
}

@MainActor
final class FloatingPanelController {
    private let panel: FloatingPanel
    private let timer: TimerViewModel

    init(timer: TimerViewModel) {
        self.timer = timer
        let content = NSHostingView(rootView: V0FloatingTimerView(timer: timer))
        panel = FloatingPanel(contentView: content)
    }

    func show() {
        panel.center()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func handleSleep() {
        timer.handleSleep()
    }

    func prepareForTermination() {
        timer.prepareForTermination()
    }
}

@MainActor
final class FloatingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 238),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentView = contentView
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TimerViewModel: ObservableObject {
    @Published private(set) var engine: TimerEngine
    @Published private(set) var activities: [Activity]
    @Published private(set) var selectedActivityID: UUID?
    @Published private(set) var records: [FocusRecord]
    private var ticker: Timer?
    private let stateStore: LocalStateStore
    private var activeSegment: ActiveFocusSegment?

    var now: Date { Date() }
    var todayFocus: TimeInterval {
        guard let today = FocusStatistics.dayInterval(for: now) else { return 0 }
        return FocusStatistics.total(records: allRecords, during: today)
    }
    var remainingBreak: TimeInterval { engine.remainingBreakSeconds(at: now) }
    var remainingRest: TimeInterval { engine.remainingRestSeconds(at: now) }
    var selectedActivity: Activity? { activities.first { $0.id == selectedActivityID && $0.status == .active } }
    var selectableActivities: [Activity] { activities.filter { $0.status == .active } }
    var canStart: Bool { selectedActivity != nil && (engine.status == .idle || engine.status == .paused) }
    var allRecords: [FocusRecord] {
        var result = records
        if let activeSegment {
            let focusedSeconds = max(0, engine.activeFocus(at: now) - activeSegment.focusAtStart)
            if focusedSeconds > 0 {
                result.append(FocusRecord(
                    activityID: activeSegment.activityID,
                    startedAt: activeSegment.startedAt,
                    endedAt: activeSegment.startedAt.addingTimeInterval(focusedSeconds)
                ))
            }
        }
        return result
    }

    init(stateStore: LocalStateStore = LocalStateStore()) {
        self.stateStore = stateStore
        guard let restored = stateStore.load() else {
            engine = TimerEngine()
            activities = []
            selectedActivityID = nil
            records = []
            activeSegment = nil
            return
        }

        engine = restored.engine
        activities = restored.activities
        selectedActivityID = restored.selectedActivityID
        records = restored.records
        activeSegment = restored.activeSegment

        if engine.status == .running {
            finishActiveSegment(at: restored.savedAt)
            engine.pause(at: restored.savedAt)
            persist(at: restored.savedAt)
        }
        if engine.status == .resting { beginTicking() }
    }

    func startOrResume() {
        guard canStart, let activityID = selectedActivityID else { return }
        if engine.status == .paused {
            engine.resume(at: now)
        } else {
            engine.start(at: now)
        }
        activeSegment = ActiveFocusSegment(
            activityID: activityID,
            startedAt: now,
            focusAtStart: engine.activeFocus(at: now)
        )
        beginTicking()
        persist()
        scheduleFocusReminder()
        refresh()
    }

    func pause() {
        guard engine.status == .running else { return }
        finishActiveSegment(at: now)
        engine.pause(at: now)
        LocalNotificationManager.shared.cancelFocusReminder()
        persist()
        refresh()
    }

    func stop() {
        guard engine.status == .running || engine.status == .paused else { return }
        if engine.status == .running { finishActiveSegment(at: now) }
        engine.stop(at: now)
        LocalNotificationManager.shared.cancelFocusReminder()
        ticker?.invalidate()
        ticker = nil
        persist()
        refresh()
    }

    func selectActivity(_ activityID: UUID) {
        guard activities.contains(where: { $0.id == activityID && $0.status == .active }) else { return }
        if engine.status == .running { pause() }
        selectedActivityID = activityID
        persist()
        refresh()
    }

    @discardableResult
    func createActivity(named name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !activities.contains(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) else { return false }
        if engine.status == .running { pause() }
        let activity = Activity(name: cleanName)
        activities.append(activity)
        selectedActivityID = activity.id
        persist()
        refresh()
        return true
    }

    func renameActivity(_ activityID: UUID, to name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty,
              !activities.contains(where: { $0.id != activityID && $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }),
              let index = activities.firstIndex(where: { $0.id == activityID }) else { return }
        activities[index].name = cleanName
        persist()
        refresh()
    }

    func setActivityStatus(_ activityID: UUID, to status: ActivityStatus) {
        guard let index = activities.firstIndex(where: { $0.id == activityID }) else { return }
        if selectedActivityID == activityID, status != .active {
            if engine.status == .running { pause() }
            selectedActivityID = selectableActivities.first(where: { $0.id != activityID })?.id
        }
        activities[index].status = status
        persist()
        refresh()
    }

    func deleteOrArchiveActivity(_ activityID: UUID) {
        guard let index = activities.firstIndex(where: { $0.id == activityID }) else { return }
        if records.contains(where: { $0.activityID == activityID }) {
            setActivityStatus(activityID, to: .archived)
            return
        }
        if selectedActivityID == activityID {
            if engine.status == .running { pause() }
            selectedActivityID = selectableActivities.first(where: { $0.id != activityID })?.id
        }
        activities.remove(at: index)
        persist()
        refresh()
    }

    func recordCount(for activityID: UUID) -> Int {
        records.filter { $0.activityID == activityID }.count
    }

    func handleSleep() { pause() }

    func beginBreak() {
        guard engine.status == .breakDue else { return }
        engine.beginBreak(at: now)
        LocalNotificationManager.shared.cancelFocusReminder()
        LocalNotificationManager.shared.scheduleRestCompletion(after: remainingRest)
        beginTicking()
        persist()
        refresh()
    }

    func deferBreak() {
        guard engine.status == .breakDue, let activityID = selectedActivityID else { return }
        engine.deferBreak(at: now)
        activeSegment = ActiveFocusSegment(
            activityID: activityID,
            startedAt: now,
            focusAtStart: engine.activeFocus(at: now)
        )
        beginTicking()
        scheduleFocusReminder()
        persist()
        refresh()
    }

    func skipBreak() {
        guard engine.status == .breakDue else { return }
        engine.skipBreak(at: now)
        LocalNotificationManager.shared.cancelFocusReminder()
        ticker?.invalidate()
        ticker = nil
        persist()
        refresh()
    }

    func enableNotifications() {
        LocalNotificationManager.shared.requestAuthorization { [weak self] in
            self?.scheduleCurrentReminder()
        }
    }

    func prepareForTermination() {
        if engine.status == .running { pause() } else { persist() }
    }

    private func beginTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func finishActiveSegment(at date: Date) {
        guard let activeSegment else { return }
        let focusedSeconds = max(0, engine.activeFocus(at: date) - activeSegment.focusAtStart)
        if focusedSeconds > 0 {
            records.append(FocusRecord(
                activityID: activeSegment.activityID,
                startedAt: activeSegment.startedAt,
                endedAt: activeSegment.startedAt.addingTimeInterval(focusedSeconds)
            ))
        }
        self.activeSegment = nil
    }

    private func persist(at date: Date? = nil) {
        stateStore.save(PersistedAppState(
            activities: activities,
            selectedActivityID: selectedActivityID,
            engine: engine,
            records: records,
            activeSegment: activeSegment,
            savedAt: date ?? now
        ))
    }

    private func refresh() {
        if engine.status == .running, engine.remainingBreakSeconds(at: now) == 0 {
            finishActiveSegment(at: now)
            engine.resolveBreakDue(at: now)
            LocalNotificationManager.shared.cancelFocusReminder()
            persist()
        }
        if engine.status == .resting, engine.remainingRestSeconds(at: now) == 0 {
            engine.resolveRestCompletion(at: now)
            LocalNotificationManager.shared.cancelRestReminder()
            ticker?.invalidate()
            ticker = nil
            persist()
        }
        objectWillChange.send()
    }

    private func scheduleCurrentReminder() {
        switch engine.status {
        case .running: scheduleFocusReminder()
        case .resting: LocalNotificationManager.shared.scheduleRestCompletion(after: remainingRest)
        default: break
        }
    }

    private func scheduleFocusReminder() {
        LocalNotificationManager.shared.scheduleFocusReminder(after: remainingBreak)
    }
}

struct V0FloatingTimerView: View {
    @ObservedObject var timer: TimerViewModel

    var body: some View {
        VStack(spacing: 10) {
            activityPicker

            HStack(spacing: 26) {
                TimerRing(
                    label: "今天",
                    value: formatTodayTotal(timer.todayFocus),
                    progress: min(timer.todayFocus / (8 * 60 * 60), 1),
                    color: WorkRhythmStyle.focus,
                    valueFontSize: 25
                )
                TimerRing(
                    label: rightRingLabel,
                    value: format(rightRingValue),
                    progress: rightRingProgress,
                    color: rightRingColor,
                    valueFontSize: 25
                )
            }

            if timer.engine.status == .breakDue {
                HStack(spacing: 8) {
                    Button("开始休息") { timer.beginBreak() }
                    Button("延后10分") { timer.deferBreak() }
                    Button("跳过") { timer.skipBreak() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if timer.engine.status == .resting {
                Text("休息中 · \(format(timer.remainingRest))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Color.clear
                    .frame(width: 304, height: 30)
                    .overlay {
                    Button(primaryActionLabel) {
                        timer.engine.status == .running ? timer.pause() : timer.startOrResume()
                    }
                    .disabled(timer.engine.status != .running && !timer.canStart)
                    .buttonStyle(FloatingPrimaryButtonStyle(isQuiet: timer.engine.status == .running))
                    }
                    .overlay(alignment: .trailing) {

                    Menu {
                        Button("结束") { timer.stop() }
                            .disabled(timer.engine.status == .idle)
                        Divider()
                        Button("开启系统提醒") { timer.enableNotifications() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 28)
                            .background(WorkRhythmStyle.controlSurface, in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: 344, height: 238)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: WorkRhythmStyle.floatingCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WorkRhythmStyle.floatingCornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
        }
    }

    private var primaryActionLabel: String {
        switch timer.engine.status {
        case .running: "暂停"
        case .paused: "继续"
        default: "开始"
        }
    }

    private var activityPicker: some View {
        HStack {
            Spacer()
            Menu {
                if timer.selectableActivities.isEmpty {
                    Text("请先在复盘窗口创建活动")
                } else {
                    ForEach(timer.selectableActivities) { activity in
                        Button {
                            timer.selectActivity(activity.id)
                        } label: {
                            if timer.selectedActivityID == activity.id {
                                Label(activity.name, systemImage: "checkmark")
                            } else {
                                Text(activity.name)
                            }
                        }
                    }
                }
            } label: {
                Text(timer.selectedActivity?.name ?? "选择活动")
                    .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(WorkRhythmStyle.controlSurface, in: Capsule())
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .font(.system(size: 13, weight: .medium))
    }

    private var rightRingLabel: String {
        switch timer.engine.status {
        case .breakDue: "该休息了"
        case .resting: "休息中"
        default: "下次休息"
        }
    }

    private var rightRingValue: TimeInterval {
        timer.engine.status == .resting ? timer.remainingRest : timer.remainingBreak
    }

    private var rightRingProgress: Double {
        switch timer.engine.status {
        case .breakDue: 1
        case .resting: 1 - timer.remainingRest / (5 * 60)
        default: timer.remainingBreak / (50 * 60)
        }
    }

    private var rightRingColor: Color {
        timer.engine.status == .resting
            ? WorkRhythmStyle.rest
            : WorkRhythmStyle.focus
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatTodayTotal(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds.rounded(.down)) / 60
        return String(format: "%02d:%02d", totalMinutes / 60, totalMinutes % 60)
    }
}

struct TimerRing: View {
    let label: String
    let value: String
    let progress: Double
    let color: Color
    let valueFontSize: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.08), lineWidth: 9)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: 114, height: 114)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}

enum WorkRhythmStyle {
    static let floatingCornerRadius: CGFloat = 22
    static let focus = Color(red: 0.29, green: 0.33, blue: 0.54)
    static let rest = Color(red: 0.52, green: 0.42, blue: 0.32)
    static let controlSurface = Color.primary.opacity(0.07)
}

struct FloatingPrimaryButtonStyle: ButtonStyle {
    let isQuiet: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isQuiet {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 22)
                .frame(height: 30)
        } else {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 22)
                .frame(height: 30)
                .background(WorkRhythmStyle.focus.opacity(configuration.isPressed ? 0.76 : 1), in: Capsule())
        }
    }
}
