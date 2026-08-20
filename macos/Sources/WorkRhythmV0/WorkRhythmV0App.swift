import AppKit
import Combine
import SwiftUI
import TimerCore

@main
struct WorkRhythmV0App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Work Rhythm", systemImage: "timer") {
            Button("显示浮窗") {
                appDelegate.showPanel()
            }
            Button("隐藏浮窗") {
                appDelegate.hidePanel()
            }
            Divider()
            Button("退出测试") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        panelController = FloatingPanelController()
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
    private let timer = TimerViewModel()

    init() {
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
        timer.simulateSleep()
    }

    func prepareForTermination() {
        timer.prepareForTermination()
    }
}

@MainActor
final class FloatingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 344, height: 314),
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
    @Published private(set) var offset: TimeInterval = 0
    private var ticker: Timer?
    private let stateStore: LocalStateStore
    private var activeSegment: ActiveFocusSegment?

    var now: Date { Date().addingTimeInterval(offset) }
    var todayFocus: TimeInterval { engine.todayFocus(at: now) }
    var remainingBreak: TimeInterval { engine.remainingBreakSeconds(at: now) }
    var selectedActivity: Activity? { activities.first { $0.id == selectedActivityID } }
    var canStart: Bool { selectedActivity != nil && engine.status != .breakDue }

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
        refresh()
    }

    func pause() {
        guard engine.status == .running else { return }
        finishActiveSegment(at: now)
        engine.pause(at: now)
        persist()
        refresh()
    }

    func stop() {
        guard engine.status == .running || engine.status == .paused else { return }
        if engine.status == .running { finishActiveSegment(at: now) }
        engine.stop(at: now)
        ticker?.invalidate()
        ticker = nil
        persist()
        refresh()
    }

    func selectActivity(_ activityID: UUID) {
        guard activities.contains(where: { $0.id == activityID }) else { return }
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

    func advance(minutes: Int) { offset += TimeInterval(minutes * 60); refresh() }
    func simulateSleep() { pause() }

    func prepareForTermination() {
        if engine.status == .running { pause() } else { persist() }
    }

    func resetDebugData() {
        ticker?.invalidate()
        ticker = nil
        engine = TimerEngine()
        activities = []
        selectedActivityID = nil
        records = []
        activeSegment = nil
        offset = 0
        stateStore.reset()
        refresh()
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
                id: UUID(),
                activityID: activeSegment.activityID,
                startedAt: activeSegment.startedAt,
                endedAt: date,
                focusedSeconds: focusedSeconds
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
            persist()
        }
        objectWillChange.send()
    }
}

struct V0FloatingTimerView: View {
    @ObservedObject var timer: TimerViewModel
    @State private var isCreatingActivity = false
    @State private var newActivityName = ""

    var body: some View {
        VStack(spacing: 11) {
            HStack {
                Text("WORK RHYTHM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                Text("V2 测试样机")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 18) {
                TimerRing(
                    label: "今天累计",
                    value: format(timer.todayFocus),
                    detail: "有效专注时长",
                    progress: min(timer.todayFocus / (8 * 60 * 60), 1),
                    color: Color(red: 0.36, green: 0.34, blue: 0.86)
                )
                TimerRing(
                    label: timer.engine.status == .breakDue ? "该休息了" : "下次休息",
                    value: format(timer.remainingBreak),
                    detail: timer.engine.status == .breakDue ? "待开始休息" : "剩余专注时间",
                    progress: timer.remainingBreak / (50 * 60),
                    color: Color(red: 0.17, green: 0.65, blue: 0.47)
                )
            }

            HStack(spacing: 6) {
                Menu {
                    if timer.activities.isEmpty {
                        Text("先新建一个长期活动")
                    } else {
                        ForEach(timer.activities) { activity in
                            Button(activity.name) { timer.selectActivity(activity.id) }
                        }
                    }
                } label: {
                    Label(timer.selectedActivity?.name ?? "选择活动", systemImage: "bookmark")
                        .lineLimit(1)
                }
                .menuStyle(.borderlessButton)

                Spacer()

                Button(isCreatingActivity ? "取消" : "新建") {
                    isCreatingActivity.toggle()
                    if !isCreatingActivity { newActivityName = "" }
                }
                .buttonStyle(.borderless)
            }
            .font(.system(size: 11, weight: .medium))

            if isCreatingActivity {
                HStack(spacing: 6) {
                    TextField("例如：看论文", text: $newActivityName)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") {
                        if timer.createActivity(named: newActivityName) {
                            newActivityName = ""
                            isCreatingActivity = false
                        }
                    }
                    .disabled(newActivityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if timer.engine.status == .breakDue {
                Text("专注周期已完成")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 7) {
                    Button(primaryActionLabel) { timer.startOrResume() }
                        .disabled(!timer.canStart || timer.engine.status == .running)
                    Button("暂停") { timer.pause() }.disabled(timer.engine.status != .running)
                    Button("结束") { timer.stop() }.disabled(timer.engine.status == .idle)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

#if DEBUG
            HStack(spacing: 8) {
                Button("+1 分钟") { timer.advance(minutes: 1) }
                Button("+50 分钟") { timer.advance(minutes: 50) }
                Button("模拟睡眠") { timer.simulateSleep() }
                Button("重置测试") { timer.resetDebugData() }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10))
#endif

            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 344, height: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.65), lineWidth: 1)
        }
    }

    private var statusText: String {
        switch timer.engine.status {
        case .idle: "测试数据仅本机保存"
        case .running: "正在专注 · 测试数据仅本机保存"
        case .paused: "已暂停 · 测试数据仅本机保存"
        case .breakDue: "专注周期完成 · 待开始休息"
        }
    }

    private var primaryActionLabel: String {
        switch timer.engine.status {
        case .paused: "继续"
        case .running: "进行中"
        default: "开始"
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct TimerRing: View {
    let label: String
    let value: String
    let detail: String
    let progress: Double
    let color: Color

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
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(detail)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 114, height: 114)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)，\(detail)")
    }
}
