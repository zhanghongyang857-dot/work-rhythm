import AppKit
import SwiftUI

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: FloatingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        panelController = FloatingPanelController()
        showPanel()
    }

    func showPanel() {
        panelController?.show()
    }

    func hidePanel() {
        panelController?.hide()
    }
}

final class FloatingPanelController {
    private let panel: FloatingPanel

    init() {
        let content = NSHostingView(rootView: V0FloatingTimerView())
        panel = FloatingPanel(contentView: content)
    }

    func show() {
        panel.center()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

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

struct V0FloatingTimerView: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("WORK RHYTHM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(1.4)
                Spacer()
                Text("V0 测试样机")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 18) {
                TimerRing(
                    label: "今天累计",
                    value: "2:15",
                    detail: "有效专注时长",
                    progress: 0.62,
                    color: Color(red: 0.36, green: 0.34, blue: 0.86)
                )
                TimerRing(
                    label: "下次休息",
                    value: "12:34",
                    detail: "剩余专注时间",
                    progress: 0.25,
                    color: Color(red: 0.17, green: 0.65, blue: 0.47)
                )
            }

            Text("仅验证浮窗外观与桌面行为，不计时、不保存数据")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 312, height: 236)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.65), lineWidth: 1)
        }
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
