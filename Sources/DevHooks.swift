import AppKit
import Foundation

// MARK: - 开发 / 自动化验收钩子

/// 所有仅用于本地自动化验收的开关都集中在这里，通过环境变量触发。
/// 正常双击启动时环境变量为空，不会执行任何逻辑。
@MainActor
enum DevHooks {
    struct Context {
        let store: TaskStore
        let settings: AppSettings
        let statusController: StatusItemController
        let reminderCenter: ReminderCenter
        let bus: CommandBus
    }

    static var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// 强制深色外观（用于深色模式截图验收）
    static func applyAppearanceIfNeeded() {
        applyDarkAppearanceToAllWindows()
    }

    static func applyDarkAppearanceToAllWindows() {
        guard environment["SCHEDULEMEMO_DARK"] == "1" else { return }
        let dark = NSAppearance(named: .darkAqua)
        NSApp.appearance = dark
        for window in NSApp.windows {
            window.appearance = dark
        }
    }

    static func run(context: Context) {
        let env = environment

        if let rawMode = env["SCHEDULEMEMO_MENUBAR_MODE"],
           let mode = MenuBarTextMode(rawValue: rawMode) {
            context.settings.menuBarMode = mode
        }

        if let reportPath = env["SCHEDULEMEMO_DEBUG_REPORT"] {
            writeDebugReport(context: context, to: reportPath, label: "initial", after: 1.2)
            writeDebugReport(context: context, to: reportPath, label: "shown", after: 2.4)
            if env["SCHEDULEMEMO_OPEN_EDITOR"] == "1" || env["SCHEDULEMEMO_OPEN_SETTINGS"] == "1" {
                writeDebugReport(context: context, to: reportPath, label: "overlay", after: 3.4)
            }
        }

        if env["SCHEDULEMEMO_SHOW_POPOVER_ON_LAUNCH"] == "1" {
            after(0.8) {
                context.statusController.showPopover()
                after(0.25) { applyDarkAppearanceToAllWindows() }
                if env["SCHEDULEMEMO_OPEN_EDITOR"] == "1" {
                    after(0.6) { context.bus.createRequest += 1 }
                }
                if env["SCHEDULEMEMO_OPEN_SETTINGS"] == "1" {
                    after(0.6) { context.bus.settingsRequest += 1 }
                }
                if env["SCHEDULEMEMO_SMOKE_ESCAPE"] == "1" {
                    after(1.4) { sendEscape() }
                    after(2.2) {
                        writeExtra(context: context, key: "escape", value: [
                            "shownAfterEscape": context.statusController.isPopoverVisible
                        ])
                    }
                }
                if env["SCHEDULEMEMO_SMOKE_ESCAPE_EDITOR"] == "1" {
                    after(1.0) {
                        sendEscape()
                        after(0.9) {
                            writeExtra(context: context, key: "escapeEditor", value: [
                                "shownAfterEscape": context.statusController.isPopoverVisible,
                                "contentHeight": context.statusController.debugSnapshot()["popoverContentHeight"] ?? -1
                            ])
                        }
                    }
                }
            }
        }

        if env["SCHEDULEMEMO_SMOKE_CLICK"] == "1" {
            after(1.5) {
                let before = context.statusController.isPopoverVisible
                context.statusController.simulateStatusClick()
                after(0.8) {
                    let afterOpen = context.statusController.isPopoverVisible
                    context.statusController.simulateStatusClick()
                    after(0.8) {
                        let afterClose = context.statusController.isPopoverVisible
                        writeExtra(context: context, key: "smoke", value: [
                            "popoverBeforeClick": before,
                            "popoverAfterFirstClick": afterOpen,
                            "popoverAfterSecondClick": afterClose,
                            "clickPathOK": !before && afterOpen && !afterClose
                        ])
                        writeDebugReport(context: context, to: env["SCHEDULEMEMO_DEBUG_REPORT"] ?? "", label: "final", after: 0.2)
                    }
                }
            }
        }

        if env["SCHEDULEMEMO_SMOKE_TYPE"] == "1" {
            after(2.2) {
                simulateTypingQuickAdd(text: "明天 10:00 评审")
                after(1.2) {
                    var info: [String: Any] = ["itemCount": context.store.items.count]
                    if let first = context.store.items.first {
                        info["firstTitle"] = first.title
                        info["firstAllDay"] = first.isAllDay
                        info["firstDue"] = ISO8601DateFormatter().string(from: first.due)
                        info["firstReminder"] = first.reminderMinutes ?? -1
                    }
                    writeExtra(context: context, key: "typing", value: info)
                }
            }
        }

        if env["SCHEDULEMEMO_SMOKE_MENUBAR"] == "1" {
            after(1.8) {
                var result: [String: Any] = [
                    "defaultTitle": context.statusController.debugSnapshot()["statusTitle"] as? String ?? ""
                ]
                context.settings.menuBarMode = .next
                after(0.4) {
                    result["nextModeTitle"] = context.statusController.debugSnapshot()["statusTitle"] as? String ?? ""
                    context.settings.menuBarMode = .count
                    after(0.4) {
                        result["countModeTitle"] = context.statusController.debugSnapshot()["statusTitle"] as? String ?? ""
                        context.settings.menuBarMode = .iconOnly
                        after(0.4) {
                            result["iconOnlyTitle"] = context.statusController.debugSnapshot()["statusTitle"] as? String ?? ""
                            writeExtra(context: context, key: "menuBarModes", value: result)
                        }
                    }
                }
            }
        }

        if env["SCHEDULEMEMO_TEST_REMINDER"] == "1" {
            after(1.5) { context.reminderCenter.presentDemo() }
        }

        if env["SCHEDULEMEMO_LOGIN_ITEM_TEST"] == "1" {
            after(1.2) {
                context.settings.setLaunchAtLogin(true)
                let enabled = context.settings.launchAtLogin
                let error = context.settings.loginItemError ?? ""
                after(1.0) {
                    context.settings.setLaunchAtLogin(false)
                    writeExtra(context: context, key: "loginItem", value: [
                        "enabledAfterRegister": enabled,
                        "error": error,
                        "enabledAfterUnregister": context.settings.launchAtLogin
                    ])
                }
            }
        }

        if let raw = env["SCHEDULEMEMO_AUTO_QUIT_SECONDS"], let seconds = Double(raw) {
            after(seconds) { NSApp.terminate(nil) }
        }
    }

    // MARK: 取景 / 报告

    private static func after(_ delay: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated(block)
        }
    }

    private static func popoverWindow() -> NSWindow? {
        NSApp.windows.first { String(describing: type(of: $0)).contains("Popover") }
    }

    private static func sendEscape() {
        guard let window = popoverWindow() else { return }
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else { return }
        NSApp.sendEvent(event)
    }

    private static func simulateTypingQuickAdd(text: String) {
        guard let window = popoverWindow() else { return }
        window.makeKey()
        after(0.1) {
            for character in text {
                let string = String(character)
                guard let event = NSEvent.keyEvent(
                    with: .keyDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    characters: string,
                    charactersIgnoringModifiers: string,
                    isARepeat: false,
                    keyCode: 0
                ) else { continue }
                NSApp.sendEvent(event)
            }
            if let enter = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            ) {
                NSApp.sendEvent(enter)
            }
        }
    }

    private static func writeDebugReport(
        context: Context,
        to path: String,
        label: String,
        after delay: TimeInterval
    ) {
        guard !path.isEmpty else { return }
        after(delay) {
            var payload: [String: Any] = context.statusController.debugSnapshot()
            payload["label"] = label
            payload["dataPath"] = AppPaths.dataFile.path
            payload["timestamp"] = Date().timeIntervalSince1970
            var all = readJSON(at: path)
            var reports = all["reports"] as? [[String: Any]] ?? []
            reports.append(payload)
            all["reports"] = reports
            writeJSON(all, to: path)
        }
    }

    private static func writeExtra(context: Context, key: String, value: [String: Any]) {
        guard let path = environment["SCHEDULEMEMO_DEBUG_REPORT"], !path.isEmpty else { return }
        var all = readJSON(at: path)
        all[key] = value
        writeJSON(all, to: path)
    }

    private static func readJSON(at path: String) -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private static func writeJSON(_ object: [String: Any], to path: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}