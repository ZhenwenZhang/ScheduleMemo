import AppKit
import SwiftUI
import Combine

// MARK: - 应用入口

@main
struct ScheduleMemoMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

// MARK: - 应用生命周期

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TaskStore!
    private var settings: AppSettings!
    private var layout: PopoverLayout!
    private var bus: CommandBus!
    private var statusController: StatusItemController!
    private var reminderCenter: ReminderCenter!
    private var keyMonitor: Any?
    private var distributedObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 同一份 App 被重复双击时，把已有实例的面板唤到前面，然后退出本次启动
        if terminateIfDuplicate() {
            NSApp.terminate(nil)
            return
        }

        DevHooks.applyAppearanceIfNeeded()

        settings = AppSettings()
        store = TaskStore()
        store.seedDemoIfRequested()
        layout = PopoverLayout()
        bus = CommandBus()

        statusController = StatusItemController(
            store: store,
            settings: settings,
            layout: layout,
            bus: bus,
            onQuit: { NSApp.terminate(nil) },
            onOpenDataFolder: { [weak self] in self?.revealDataFolder() }
        )

        reminderCenter = ReminderCenter(
            store: store,
            settings: settings,
            isPopoverVisible: { [weak self] in self?.statusController?.isPopoverVisible ?? false }
        )
        reminderCenter.start()

        // 面板打开时会暂缓提醒；关闭后立即补检查一次，避免错过
        statusController.onPopoverDidClose = { [weak self] in
            self?.reminderCenter.checkDue()
        }

        // 另一个实例请求唤出面板
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: .showPanelRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                self?.statusController.showPopover()
            }
        }

        installKeyMonitor()
        showFirstRunPopoverIfNeeded()
        DevHooks.run(context: DevHooks.Context(
            store: store,
            settings: settings,
            statusController: statusController,
            reminderCenter: reminderCenter,
            bus: bus
        ))
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 已运行时再次打开（例如在 Finder 里双击）直接唤出面板
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.showPopover()
        return true
    }

    // MARK: 键盘

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Esc：关闭表单/设置，否则收起面板（只处理面板自身为当前窗口的情况）
            if event.keyCode == 53, self.statusController.isPopoverVisible,
               NSApp.keyWindow === self.statusController.popoverWindow {
                self.bus.escapeRequest += 1
                return nil
            }

            // ⌘N 新建日程
            if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "n" {
                self.bus.createRequest += 1
                return nil
            }
            return event
        }
    }

    // MARK: 首次启动

    private func showFirstRunPopoverIfNeeded() {
        let isFirstRun = !FileManager.default.fileExists(atPath: AppPaths.dataFile.path)
        guard isFirstRun else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.statusController.showPopover()
        }
    }

    // MARK: 数据目录

    private func revealDataFolder() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: AppPaths.dataDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: AppPaths.dataFile.path) {
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.dataFile])
        } else {
            NSWorkspace.shared.open(AppPaths.dataDirectory)
        }
    }

    // MARK: 单实例

    private func terminateIfDuplicate() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let duplicates = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter {
            $0.processIdentifier != currentPID && $0.bundleURL?.standardizedFileURL == currentURL
        }
        guard !duplicates.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(
            .showPanelRequested,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
}

extension Notification.Name {
    static let showPanelRequested = Notification.Name("ScheduleMemo.showPanelRequested")
}