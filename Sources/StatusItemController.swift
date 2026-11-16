import AppKit
import SwiftUI
import Combine

// MARK: - 菜单栏图标与弹出面板

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: TaskStore
    private let settings: AppSettings
    private let layout: PopoverLayout
    private let bus: CommandBus

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var hosting: NSViewController?
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?
    private var globalMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// 面板关闭后的回调（用于补检查被暂缓的提醒）
    var onPopoverDidClose: (() -> Void)?

    private let onQuit: () -> Void
    private let onOpenDataFolder: () -> Void

    init(
        store: TaskStore,
        settings: AppSettings,
        layout: PopoverLayout,
        bus: CommandBus,
        onQuit: @escaping () -> Void,
        onOpenDataFolder: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.layout = layout
        self.bus = bus
        self.onQuit = onQuit
        self.onOpenDataFolder = onOpenDataFolder
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusButton()
        configurePopover()
        bindUpdates()
        updateStatusItem()
        startRefreshTimer()
    }

    // MARK: 图标

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "日程备忘录")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        button.target = self
        button.action = #selector(statusButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "日程备忘录"
    }

    private func startRefreshTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateStatusItem() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func bindUpdates() {
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        settings.$menuBarMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        layout.$height
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] height in
                guard let self else { return }
                self.popover.contentSize = NSSize(width: PopoverLayout.width, height: height)
            }
            .store(in: &cancellables)

        bus.$settingsRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.showPopover()
            }
            .store(in: &cancellables)
    }

    /// 普通文案用系统默认颜色（自动适配浅色/深色菜单栏）；逾期时用红色。
    private func applyStatusTitle(_ text: String?, alert: Bool) {
        guard let button = statusItem.button else { return }
        if let text, !text.isEmpty, alert {
            button.attributedTitle = NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
                    .foregroundColor: NSColor.systemRed
                ]
            )
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = text ?? ""
        }
    }

    func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let now = Date()
        let result = ScheduleLogic.menuBarText(items: store.items, now: now, mode: settings.menuBarMode)
        applyStatusTitle(result.text, alert: result.alert)

        let summary = ScheduleLogic.statusSummary(items: store.items, now: now)
        var tooltip = "日程备忘录 · 未完成 \(ScheduleLogic.pendingCount(items: store.items)) 项"
        if summary.overdue > 0 { tooltip += " · 逾期 \(summary.overdue) 项" }
        if summary.todayPending > 0 { tooltip += " · 今天 \(summary.todayPending) 项" }
        if let next = summary.next {
            tooltip += "\n下一项：\(DateText.dueDescription(for: next, now: now))  \(next.title)"
        }
        if result.alert { tooltip += "\n有日程已逾期，点开处理。" }
        button.toolTip = tooltip
    }

    // MARK: 弹出面板

    private func configurePopover() {
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self

        let root = PopoverView(
            store: store,
            settings: settings,
            layout: layout,
            bus: bus,
            onQuit: onQuit,
            onDismiss: { [weak self] in self?.closePopover() },
            onOpenDataFolder: onOpenDataFolder
        )
        let controller = NSHostingController(rootView: root)
        hosting = controller
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: PopoverLayout.width, height: layout.height)

        // 验收环境可关闭自动收起，避免真人点击 / 切换应用干扰自动化截图。
        let autoCloseEnabled = ProcessInfo.processInfo.environment["SCHEDULEMEMO_DISABLE_AUTO_CLOSE"] != "1"
        guard autoCloseEnabled else { return }

        // 应用失去焦点时（⌘Tab、点到别的应用等）收起面板
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }

        // 点击其他应用 / 桌面时关闭面板。
        // 不用本地事件监视：日期选择弹窗、保存面板都属于本应用的其他窗口，
        // 用 event.window 判断"是否在面板外"会误伤它们。
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePopover() }
        }
    }

    /// 模拟左键点击状态栏图标（用于自动化验收）
    func simulateStatusClick() {
        statusItem.button?.performClick(nil)
    }

    @objc private func statusButtonClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        togglePopover()
    }

    func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.contentSize = NSSize(width: PopoverLayout.width, height: layout.height)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    var isPopoverVisible: Bool { popover.isShown }

    var popoverWindow: NSWindow? { popover.contentViewController?.view.window }

    func popoverDidClose(_ notification: Notification) {
        onPopoverDidClose?()
    }

    /// 开发验收用的状态快照（仅当设置 SCHEDULEMEMO_DEBUG_REPORT 时写出）。
    func debugSnapshot(statusResult: (String?, Bool) = (nil, false)) -> [String: Any] {
        var info: [String: Any] = [
            "statusTitle": statusItem.button?.title ?? "",
            "statusImageWidth": statusItem.button?.image?.size.width ?? 0,
            "popoverShown": popover.isShown,
            "popoverContentWidth": popover.contentSize.width,
            "popoverContentHeight": popover.contentSize.height,
            "screenWidth": NSScreen.main?.frame.width ?? 0,
            "screenHeight": NSScreen.main?.frame.height ?? 0,
            "visibleFrameY": NSScreen.main?.visibleFrame.maxY ?? 0,
            "version": AppInfo.version,
            "appearance": NSApp.appearance?.name.rawValue ?? "system",
            "windowAppearance": popoverWindow?.effectiveAppearance.name.rawValue ?? "none"
        ]
        if let window = popover.contentViewController?.view.window {
            info["popoverFrame"] = [
                "x": window.frame.origin.x, "y": window.frame.origin.y,
                "w": window.frame.width, "h": window.frame.height
            ] as [String: CGFloat]
        }
        var windows: [[String: Any]] = []
        for window in NSApp.windows where window.isVisible {
            windows.append([
                "class": String(describing: type(of: window)),
                "title": window.title,
                "frame": [
                    "x": window.frame.origin.x, "y": window.frame.origin.y,
                    "w": window.frame.width, "h": window.frame.height
                ] as [String: CGFloat],
                "level": window.level.rawValue,
                "contentHeight": window.contentView?.frame.height ?? 0
            ])
        }
        info["windows"] = windows
        var counters: [String: Any] = ["items": store.items.count]
        counters["pending"] = ScheduleLogic.pendingCount(items: store.items)
        counters["overdue"] = ScheduleLogic.overdueCount(items: store.items, now: Date())
        info["counters"] = counters
        info["dataPath"] = AppPaths.dataFile.path
        info["contextMenuItems"] = buildContextMenu().items
            .filter { !$0.isSeparatorItem }
            .map(\.title)
        info["dataFileExists"] = FileManager.default.fileExists(atPath: AppPaths.dataFile.path)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: AppPaths.dataFile.path) {
            info["dataFileSize"] = attributes[.size] as? Int ?? 0
        }
        return info
    }

    // MARK: 右键菜单

    private func showContextMenu() {
        closePopover()
        let menu = buildContextMenu()
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    private func buildContextMenu() -> NSMenu {
        let now = Date()
        let menu = NSMenu()
        let summary = ScheduleLogic.statusSummary(items: store.items, now: now)

        let openItem = NSMenuItem(title: "打开日程面板", action: #selector(menuOpenPanel), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let newItem = NSMenuItem(title: "新建日程…", action: #selector(menuNewItem), keyEquivalent: "n")
        newItem.keyEquivalentModifierMask = .command
        newItem.target = self
        menu.addItem(newItem)

        menu.addItem(.separator())

        var overview = "今天 \(summary.todayPending) 项待办"
        if summary.overdue > 0 { overview = "逾期 \(summary.overdue) 项 · " + overview }
        let overviewItem = NSMenuItem(title: overview, action: nil, keyEquivalent: "")
        overviewItem.isEnabled = false
        menu.addItem(overviewItem)

        if let next = summary.next {
            let nextItem = NSMenuItem(
                title: "下一项：\(DateText.dueDescription(for: next, now: now)) \(DateText.shorten(next.title, limit: 14))",
                action: nil,
                keyEquivalent: ""
            )
            nextItem.isEnabled = false
            menu.addItem(nextItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        let dataItem = NSMenuItem(title: "打开数据文件夹", action: #selector(menuOpenData), keyEquivalent: "")
        dataItem.target = self
        menu.addItem(dataItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出日程备忘录", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func menuOpenPanel() {
        showPopover()
    }

    @objc private func menuNewItem() {
        showPopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.bus.createRequest += 1
        }
    }

    @objc private func menuOpenSettings() {
        showPopover()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.bus.settingsRequest += 1
        }
    }

    @objc private func menuOpenData() {
        onOpenDataFolder()
    }

    @objc private func menuQuit() {
        onQuit()
    }

    deinit {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        refreshTimer?.invalidate()
    }
}

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("ScheduleMemo.openSettingsRequested")
}