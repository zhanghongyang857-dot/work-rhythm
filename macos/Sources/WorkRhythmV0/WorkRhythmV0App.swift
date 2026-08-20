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
}

@MainActor
final class FloatingPanel: NSPanel {
    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 312, height: 236),
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
    @Published private(set) var engine = TimerEngine()
    @Published private(set) var offset: TimeInterval = 0
    private var ticker: Timer?

    var now: Date { Date().addingTimeInterval(offset) }
    var todayFocus: TimeInterval { engine.todayFocus(at: now) }
    var remainingBreak: TimeInterval { engine.remainingBreakSeconds(at: now) }

    func startOrResume() {
        if engine.status == .paused { engine.resume(at: now) } else { engine.start(at: now) }
        beginTicking()
        refresh()
    }

    func pause() { engine.pause(at: now); refresh() }
    func stop() { engine.stop(at: now); ticker?.invalidate(); ticker = nil; refresh() }
    func advance(minutes: Int) { offset += TimeInterval(minutes * 60); refresh() }
    func simulateSleep() { engine.handleSleep(at: now); refresh() }

    private func beginTicking() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        engine.resolveBreakDue(at: now)
        objectWillChange.send()
    }
}

struct V0FloatingTimerView: View {
    @ObservedObject var timer: TimerViewModel

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("WORK RHYTHM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                Text("V1 测试样机")
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

            if timer.engine.status == .breakDue {
                Text("专注周期已完成")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 7) {
                    Button(timer.engine.status == .paused ? "继续" : "开始") { timer.startOrResume() }
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
            }
            .buttonStyle(.borderless)
            .font(.system(size: 10))
#endif

            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 312, height: 278)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.65), lineWidth: 1)
        }
    }

    private var statusText: String {
        switch timer.engine.status {
        case .idle: "测试数据不会保存"
        case .running: "正在专注 · 测试数据不会保存"
        case .paused: "已暂停 · 测试数据不会保存"
        case .breakDue: "专注周期完成 · 待开始休息"
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
