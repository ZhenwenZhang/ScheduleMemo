import Foundation
import Combine
import ServiceManagement

// MARK: - 应用设置

@MainActor
final class AppSettings: ObservableObject {
    enum Keys {
        static let menuBarMode = "menuBarMode"
        static let defaultReminder = "defaultReminderMinutes"
        static let launchAtLogin = "launchAtLogin"
        static let showDoneSection = "showDoneSection"
        static let soundEnabled = "soundEnabled"
    }

    @Published var menuBarMode: MenuBarTextMode {
        didSet { defaults.set(menuBarMode.rawValue, forKey: Keys.menuBarMode) }
    }

    /// nil 表示默认不提醒
    @Published var defaultReminderMinutes: Int? {
        didSet {
            if let value = defaultReminderMinutes {
                defaults.set(value, forKey: Keys.defaultReminder)
            } else {
                defaults.set(-1, forKey: Keys.defaultReminder)
            }
        }
    }

    /// 提醒是否播放提示音
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    @Published private(set) var launchAtLogin: Bool = false
    @Published private(set) var loginItemError: String?

    private let defaults: UserDefaults

    /// 自动化验收时使用独立域，避免改动真实使用中的偏好设置。
    private static func makeDefaults() -> UserDefaults {
        if ProcessInfo.processInfo.environment["SCHEDULEMEMO_DATA_DIR"] != nil,
           let suite = UserDefaults(suiteName: "com.zhenwenzhang.schedulememo.tests") {
            return suite
        }
        return .standard
    }

    init(defaults: UserDefaults? = nil) {
        let resolved = defaults ?? AppSettings.makeDefaults()
        self.defaults = resolved
        let storedMode = resolved.string(forKey: Keys.menuBarMode) ?? ""
        menuBarMode = MenuBarTextMode(rawValue: storedMode) ?? .next

        if resolved.object(forKey: Keys.defaultReminder) == nil {
            defaultReminderMinutes = 10
        } else {
            let value = resolved.integer(forKey: Keys.defaultReminder)
            defaultReminderMinutes = value < 0 ? nil : value
        }

        if resolved.object(forKey: Keys.soundEnabled) == nil {
            soundEnabled = true
        } else {
            soundEnabled = resolved.bool(forKey: Keys.soundEnabled)
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: 开机自启

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = launchAtLogin == enabled ? nil : "系统未确认该项设置，请到「系统设置 › 通用 › 登录项」中检查"
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = "设置失败：\(error.localizedDescription)"
        }
    }

    func refreshLaunchAtLoginStatus() {
        if defaults.object(forKey: Keys.soundEnabled) == nil {
            soundEnabled = true
        } else {
            soundEnabled = defaults.bool(forKey: Keys.soundEnabled)
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: 提醒选项

    static let reminderOptions: [(Int?, String)] = [
        (nil, "不提醒"),
        (0, "准时提醒"),
        (5, "提前 5 分钟"),
        (10, "提前 10 分钟"),
        (15, "提前 15 分钟"),
        (30, "提前 30 分钟"),
        (60, "提前 1 小时"),
        (1440, "提前 1 天")
    ]

    static func reminderLabel(_ minutes: Int?) -> String {
        guard let minutes = minutes else { return "不提醒" }
        if minutes == 0 { return "准时提醒" }
        if minutes < 60 { return "提前 \(minutes) 分钟" }
        if minutes < 1440 { return "提前 \(minutes / 60) 小时" }
        return "提前 \(minutes / 1440) 天"
    }
}

// MARK: - 面板布局

@MainActor
final class PopoverLayout: ObservableObject {
    static let width: CGFloat = 240
    static let editorHeight: CGFloat = 556
    static let settingsHeight: CGFloat = 640

    @Published var height: CGFloat = 420
}

// MARK: - 跨视图命令

@MainActor
final class CommandBus: ObservableObject {
    @Published var createRequest = 0
    @Published var settingsRequest = 0
    @Published var escapeRequest = 0
}
