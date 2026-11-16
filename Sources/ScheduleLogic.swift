import Foundation

// MARK: - 列表筛选

enum ListFilter: String, CaseIterable, Identifiable {
    case today
    case week
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "今天"
        case .week: return "7 天内"
        case .all: return "全部"
        }
    }

    var symbolName: String {
        switch self {
        case .today: return "sun.max"
        case .week: return "calendar"
        case .all: return "tray.full"
        }
    }
}

// MARK: - 分组

struct ItemSection: Identifiable, Equatable {
    enum Kind: Int {
        case overdue
        case day
        case done
    }

    let id: String
    let kind: Kind
    let title: String
    let items: [ScheduleItem]

    static func == (lhs: ItemSection, rhs: ItemSection) -> Bool {
        lhs.id == rhs.id && lhs.items.map(\.id) == rhs.items.map(\.id) && lhs.title == rhs.title
    }
}

// MARK: - 纯逻辑：分组 / 统计 / 菜单栏摘要

enum ScheduleLogic {
    /// 已完成条目在列表里保留的天数
    static let doneRetentionDays = 7

    static func pending(_ items: [ScheduleItem]) -> [ScheduleItem] {
        items.filter { !$0.isDone }
    }

    static func sections(
        items: [ScheduleItem],
        filter: ListFilter,
        now: Date,
        calendar: Calendar = ScheduleCalendar.work
    ) -> [ItemSection] {
        let todayStart = calendar.startOfDay(for: now)
        let pendingItems = items.filter { !$0.isDone }

        var result: [ItemSection] = []

        // 1. 逾期
        let overdue = pendingItems
            .filter { $0.isOverdue(now: now, calendar: calendar) }
            .sorted(by: itemSort(lhs:rhs:))
        if !overdue.isEmpty {
            result.append(ItemSection(id: "overdue", kind: .overdue, title: "已逾期", items: overdue))
        }

        // 2. 按天分组
        var buckets: [Date: [ScheduleItem]] = [:]
        for item in pendingItems where !item.isOverdue(now: now, calendar: calendar) {
            let day = calendar.startOfDay(for: item.due)
            buckets[day, default: []].append(item)
        }

        let days = buckets.keys.sorted()
        for day in days {
            let offset = calendar.dateComponents([.day], from: todayStart, to: day).day ?? 0
            switch filter {
            case .today where offset != 0:
                continue
            case .week where offset < 0 || offset > 6:
                continue
            case .today, .week, .all:
                break
            }
            guard let dayItems = buckets[day], !dayItems.isEmpty else { continue }
            let sorted = dayItems.sorted(by: itemSort(lhs:rhs:))
            result.append(ItemSection(id: sectionID(for: day, calendar: calendar), kind: .day, title: dayTitle(for: day, now: now, calendar: calendar), items: sorted))
        }

        // 3. 已完成（最近若干天）
        let cutoff = calendar.date(byAdding: .day, value: -doneRetentionDays, to: todayStart) ?? todayStart
        let done = items
            .filter { item in
                guard item.isDone else { return false }
                let stamp = item.completedAt ?? item.updatedAt
                return stamp >= cutoff
            }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
        if !done.isEmpty {
            result.append(ItemSection(id: "done", kind: .done, title: "已完成", items: done))
        }

        return result
    }

    static func itemSort(lhs: ScheduleItem, rhs: ScheduleItem) -> Bool {
        if lhs.due != rhs.due { return lhs.due < rhs.due }
        if lhs.priority.rawValue != rhs.priority.rawValue { return lhs.priority.rawValue > rhs.priority.rawValue }
        return lhs.createdAt < rhs.createdAt
    }

    /// 「下周一」这类语义的日期：严格落在下一周，而不是"最近的周一"。
    static func nextWeekStartDay(
        forWeekday weekday: Int,
        from date: Date,
        calendar: Calendar = ScheduleCalendar.work
    ) -> Date? {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
            return nil
        }
        let firstWeekday = calendar.firstWeekday
        let offset = ((weekday - firstWeekday) % 7 + 7) % 7
        return calendar.date(byAdding: .day, value: offset, to: nextWeekStart)
    }

    static func sectionID(for day: Date, calendar: Calendar = ScheduleCalendar.work) -> String {
        "day-" + DateText.isoDayKey.string(from: day)
    }

    static func dayTitle(for day: Date, now: Date, calendar: Calendar = ScheduleCalendar.work) -> String {
        let today = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let datePart = DateText.monthDayWeekday(day)
        switch offset {
        case 0: return "今天 · \(datePart)"
        case 1: return "明天 · \(datePart)"
        case 2: return "后天 · \(datePart)"
        default: return datePart
        }
    }

    // MARK: 统计

    static func overdueCount(items: [ScheduleItem], now: Date, calendar: Calendar = ScheduleCalendar.work) -> Int {
        items.filter { $0.isOverdue(now: now, calendar: calendar) }.count
    }

    static func todayPendingCount(items: [ScheduleItem], now: Date, calendar: Calendar = ScheduleCalendar.work) -> Int {
        let today = calendar.startOfDay(for: now)
        return items.filter { item in
            guard !item.isDone else { return false }
            return calendar.startOfDay(for: item.due) == today
        }.count
    }

    static func pendingCount(items: [ScheduleItem]) -> Int {
        items.filter { !$0.isDone }.count
    }

    /// 当前时刻应该弹出提醒的日程（已按提醒时间排序）。
    /// 只补弹错过不久的提醒，太久以前的交给列表里的「已逾期」。
    static func remindersDue(
        items: [ScheduleItem],
        now: Date,
        calendar: Calendar = ScheduleCalendar.work
    ) -> [ScheduleItem] {
        items
            .compactMap { item -> (item: ScheduleItem, fire: Date)? in
                guard !item.isDone, item.reminderMinutes != nil else { return nil }
                guard let fire = item.effectiveReminderDate(calendar: calendar) else { return nil }
                guard now >= fire else { return nil }
                let lateWindow: TimeInterval = item.isAllDay ? 3 * 3600 : 30 * 60
                guard now < fire.addingTimeInterval(lateWindow) else { return nil }
                guard item.notifiedFireKey != item.fireKey(calendar: calendar) else { return nil }
                return (item, fire)
            }
            .sorted { $0.fire < $1.fire }
            .map(\.item)
    }

    /// 下一条还没到期、最靠前的日程（用于菜单栏显示）。
    static func nextUpcoming(
        items: [ScheduleItem],
        now: Date,
        calendar: Calendar = ScheduleCalendar.work
    ) -> ScheduleItem? {
        let candidates = items
            .filter { !$0.isDone && !$0.isOverdue(now: now, calendar: calendar) }
            .sorted(by: itemSort(lhs:rhs:))
        // 优先今天的日程，其次未来最近的一条
        return candidates.first
    }

    struct StatusSummary: Equatable {
        let overdue: Int
        let todayPending: Int
        let next: ScheduleItem?
    }

    static func statusSummary(
        items: [ScheduleItem],
        now: Date,
        calendar: Calendar = ScheduleCalendar.work
    ) -> StatusSummary {
        StatusSummary(
            overdue: overdueCount(items: items, now: now, calendar: calendar),
            todayPending: todayPendingCount(items: items, now: now, calendar: calendar),
            next: nextUpcoming(items: items, now: now, calendar: calendar)
        )
    }

    /// 菜单栏显示的文案。nil 表示只显示图标。
    /// - Parameter mode: 显示模式（下一项 / 今日数量 / 仅图标）。
    static func menuBarText(
        items: [ScheduleItem],
        now: Date,
        mode: MenuBarTextMode,
        calendar: Calendar = ScheduleCalendar.work
    ) -> (text: String?, alert: Bool) {
        let summary = statusSummary(items: items, now: now, calendar: calendar)
        if summary.overdue > 0 {
            return ("\(summary.overdue) 项逾期", true)
        }
        guard mode != .iconOnly else { return (nil, false) }
        if mode == .count {
            return summary.todayPending > 0 ? ("\(summary.todayPending)", false) : (nil, false)
        }
        guard let next = summary.next else { return (nil, false) }
        return (DateText.menuBarLabel(for: next, now: now, calendar: calendar), false)
    }
}

// MARK: - 菜单栏显示模式

enum MenuBarTextMode: String, CaseIterable, Identifiable {
    case next
    case count
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .next: return "图标 + 下一项日程"
        case .count: return "图标 + 今日待办数"
        case .iconOnly: return "仅图标"
        }
    }
}