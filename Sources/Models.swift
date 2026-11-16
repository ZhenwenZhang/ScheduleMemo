import Foundation

// MARK: - 优先级

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 0
    case medium = 1
    case high = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        }
    }

    var symbolName: String {
        switch self {
        case .low: return "arrow.down.circle"
        case .medium: return "equal.circle"
        case .high: return "exclamationmark.circle"
        }
    }
}

// MARK: - 日程条目

struct ScheduleItem: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    /// 到期时间。全天日程的时分秒为 00:00:00。
    var due: Date
    var isAllDay: Bool
    var priority: TaskPriority
    var isDone: Bool
    /// 提前多少分钟提醒；nil 表示不提醒。
    var reminderMinutes: Int?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    /// 已经弹出过提醒的标识，避免重复提醒（值为提醒触发时间戳）。
    var notifiedFireKey: String?
    /// 「稍后提醒」的目标时间。
    var snoozeUntil: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        due: Date,
        isAllDay: Bool = false,
        priority: TaskPriority = .medium,
        isDone: Bool = false,
        reminderMinutes: Int? = 10,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        notifiedFireKey: String? = nil,
        snoozeUntil: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.due = due
        self.isAllDay = isAllDay
        self.priority = priority
        self.isDone = isDone
        self.reminderMinutes = reminderMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.notifiedFireKey = notifiedFireKey
        self.snoozeUntil = snoozeUntil
    }

    /// 容错解码：旧版本数据缺少字段时使用默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "未命名日程"
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        due = try c.decodeIfPresent(Date.self, forKey: .due) ?? Date()
        isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        priority = try c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium
        isDone = try c.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        reminderMinutes = try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? 10
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        notifiedFireKey = try c.decodeIfPresent(String.self, forKey: .notifiedFireKey)
        snoozeUntil = try c.decodeIfPresent(Date.self, forKey: .snoozeUntil)
    }

    // MARK: 时间判断

    func dueDayStart(calendar: Calendar = ScheduleCalendar.work) -> Date {
        calendar.startOfDay(for: due)
    }

    /// 是否已逾期：全天日程过了当天算逾期；定时日程过了具体时刻算逾期。
    func isOverdue(now: Date, calendar: Calendar = ScheduleCalendar.work) -> Bool {
        guard !isDone else { return false }
        if isAllDay {
            return dueDayStart(calendar: calendar) < calendar.startOfDay(for: now)
        }
        return due < now
    }

    /// 提醒应该在什么时刻触发。
    func reminderFireDate(calendar: Calendar = ScheduleCalendar.work) -> Date? {
        guard let minutes = reminderMinutes else { return nil }
        var base: Date
        if isAllDay {
            // 全天日程默认当天上午 9:00 提醒
            base = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due) ?? due
        } else {
            base = due
        }
        return base.addingTimeInterval(-Double(max(0, minutes)) * 60)
    }

    /// 考虑「稍后提醒」后，实际应提醒的时间。
    func effectiveReminderDate(calendar: Calendar = ScheduleCalendar.work) -> Date? {
        guard let base = reminderFireDate(calendar: calendar) else { return nil }
        if let snooze = snoozeUntil, snooze > base { return snooze }
        return base
    }

    func fireKey(calendar: Calendar = ScheduleCalendar.work) -> String {
        String(Int(effectiveReminderDate(calendar: calendar)?.timeIntervalSince1970 ?? 0))
    }

    static func == (lhs: ScheduleItem, rhs: ScheduleItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - 日历与格式化

enum ScheduleCalendar {
    /// 周一为一周第一天、中文习惯的日历。
    static var work: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_CN")
        cal.firstWeekday = 2
        cal.timeZone = .current
        return cal
    }
}

enum DateText {
    static let zhLocale = Locale(identifier: "zh_CN")

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = zhLocale
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    static let time = formatter("HH:mm")
    static let monthDay = formatter("M月d日")
    static let weekday = formatter("EEE")
    static let fullDate = formatter("yyyy年M月d日")
    static let yearMonthDay = formatter("yyyy年M月d日")
    static let isoDayKey = formatter("yyyy-MM-dd")

    static func monthDayWeekday(_ date: Date) -> String {
        "\(monthDay.string(from: date)) \(weekday.string(from: date))"
    }

    /// 面板顶部：2026年11月13日 周四
    static func headerDate(_ date: Date) -> String {
        "\(fullDate.string(from: date)) \(weekday.string(from: date))"
    }

    /// 相对于今天的人性化日期标签。
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar = ScheduleCalendar.work) -> String {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "今天"
        case 1: return "明天"
        case 2: return "后天"
        case -1: return "昨天"
        default: return monthDayWeekday(date)
        }
    }

    /// 列表行右侧时间/日期说明。
    static func dueDescription(for item: ScheduleItem, now: Date, calendar: Calendar = ScheduleCalendar.work) -> String {
        if item.isAllDay { return "全天" }
        let day = calendar.startOfDay(for: item.due)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0

        var datePart: String
        switch days {
        case 0: datePart = ""
        case 1: datePart = "明天"
        case 2: datePart = "后天"
        case -1: datePart = "昨天"
        default: datePart = monthDay.string(from: item.due)
        }

        let timePart: String? = item.isAllDay ? nil : time.string(from: item.due)

        switch (datePart.isEmpty, timePart) {
        case (true, let t?): return t
        case (true, nil): return "全天"
        case (false, let t?): return "\(datePart) \(t)"
        case (false, nil): return datePart
        }
    }

    /// 菜单栏上的简短文字。
    static func menuBarLabel(for item: ScheduleItem, now: Date, calendar: Calendar = ScheduleCalendar.work) -> String {
        let title = shorten(item.title, limit: 10)
        let day = calendar.startOfDay(for: item.due)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0

        let datePrefix: String
        switch days {
        case 0: datePrefix = ""
        case 1: datePrefix = "明天 "
        default: datePrefix = monthDay.string(from: item.due) + " "
        }

        if item.isAllDay {
            if days == 0 { return title }
            return datePrefix + title
        }
        return datePrefix + time.string(from: item.due) + " " + title
    }

    static func shorten(_ text: String, limit: Int) -> String {
        let chars = Array(text)
        if chars.count <= limit { return text }
        return String(chars.prefix(limit)) + "…"
    }
}

// MARK: - 存储路径

enum AppPaths {
    static let appFolderName = "ScheduleMemo"

    static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["SCHEDULEMEMO_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(appFolderName, isDirectory: true)
    }

    static var dataFile: URL {
        dataDirectory.appendingPathComponent("schedules.json")
    }

    static var backupFile: URL {
        dataDirectory.appendingPathComponent("schedules.backup.json")
    }
}