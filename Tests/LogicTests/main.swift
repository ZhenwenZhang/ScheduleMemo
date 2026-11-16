import Foundation

// 轻量测试运行器：swiftc 直接编译运行，不依赖 XCTest。
var failures = 0
var passes = 0

func expect(_ condition: Bool, _ message: @autoclosure () -> String, file: String = #file, line: Int = #line) {
    if condition {
        passes += 1
    } else {
        failures += 1
        print("❌ FAIL [\(line)] \(message())")
    }
}

func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ label: String, line: Int = #line) {
    if lhs == rhs {
        passes += 1
    } else {
        failures += 1
        print("❌ FAIL [\(line)] \(label): 期望 \(rhs)，实际 \(lhs)")
    }
}

// MARK: - 固定时间：2026-11-13 周五 10:00

let cal = ScheduleCalendar.work
let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 10, minute: 0))!

func day(_ offset: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    let base = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!
    return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
}

func ymd(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    f.timeZone = .current
    return f.string(from: d)
}

// MARK: - 自然语言解析

func testParser() {
    let p1 = QuickAddParser.parse("明天 10:00 交报告", now: now)
    expectEqual(p1.title, "交报告", "解析标题")
    expectEqual(ymd(p1.due), "2026-11-14 10:00", "明天10点")
    expect(!p1.isAllDay, "带时间不是全天")

    let p2 = QuickAddParser.parse("今天下午3点 和周总开会", now: now)
    expectEqual(p2.title, "和周总开会", "解析标题2")
    expectEqual(ymd(p2.due), "2026-11-13 15:00", "今天下午3点")

    let p3 = QuickAddParser.parse("周三 上午9点半 复盘", now: now)
    expectEqual(ymd(p3.due), "2026-11-18 09:30", "下周三9点半")
    expectEqual(p3.title, "复盘", "周三标题")

    let p4 = QuickAddParser.parse("11月20日 提交材料", now: now)
    expectEqual(ymd(p4.due), "2026-11-20 00:00", "11月20日")
    expect(p4.isAllDay, "只有日期是全天")
    expectEqual(p4.title, "提交材料", "标题4")

    let p5 = QuickAddParser.parse("买牛奶", now: now)
    expectEqual(ymd(p5.due), "2026-11-13 00:00", "无日期默认今天全天")
    expect(p5.isAllDay, "无时间全天")
    expectEqual(p5.title, "买牛奶", "纯标题")
    expect(!p5.matchedDate && !p5.matchedTime, "无日期时间匹配")

    let p6 = QuickAddParser.parse("3天后 取快递", now: now)
    expectEqual(ymd(p6.due), "2026-11-16 00:00", "3天后")
    expectEqual(p6.title, "取快递", "标题6")

    let p7 = QuickAddParser.parse("晚上8点 健身房", now: now)
    expectEqual(ymd(p7.due), "2026-11-13 20:00", "晚上8点")

    let p8 = QuickAddParser.parse("12/25 圣诞聚会", now: now)
    expectEqual(ymd(p8.due), "2026-12-25 00:00", "12/25")
    expectEqual(p8.title, "圣诞聚会", "标题8")

    let p9 = QuickAddParser.parse("9:30", now: now)
    expectEqual(p9.title, "新日程", "只有时间时标题兜底")
    expectEqual(ymd(p9.due), "2026-11-14 09:30", "已过点顺延到明天")

    let p10 = QuickAddParser.parse("2026-12-01 14:30 项目评审", now: now)
    expectEqual(ymd(p10.due), "2026-12-01 14:30", "完整日期时间")
    expectEqual(p10.title, "项目评审", "标题10")

    let p11 = QuickAddParser.parse("中午12点 午餐", now: now)
    expectEqual(ymd(p11.due), "2026-11-13 12:00", "中午12点")

    let p12 = QuickAddParser.parse("凌晨2点 看球", now: now)
    expectEqual(ymd(p12.due), "2026-11-14 02:00", "凌晨2点顺延")

    let p13 = QuickAddParser.parse("20号 交材料", now: now)
    expectEqual(ymd(p13.due), "2026-11-20 00:00", "20号")

    let p14 = QuickAddParser.parse("大后天 下午 开会", now: now)
    expectEqual(ymd(p14.due), "2026-11-16 15:00", "大后天下午")
    expectEqual(p14.title, "开会", "标题14")

    let p15 = QuickAddParser.parse("下周一 9点 晨会", now: now)
    expectEqual(ymd(p15.due), "2026-11-16 09:00", "下周一9点")
    expectEqual(p15.title, "晨会", "标题15")

    let p16 = QuickAddParser.parse("今天 18:00 下班", now: now)
    expectEqual(ymd(p16.due), "2026-11-13 18:00", "今天18点")

    let p17 = QuickAddParser.parse("周五 9点 周会", now: now)
    expectEqual(ymd(p17.due), "2026-11-20 09:00", "今天周五已过点则下周五")

    let p18 = QuickAddParser.parse("明天 全天 团建", now: now)
    expect(p18.isAllDay, "全天关键词")
    expectEqual(ymd(p18.due), "2026-11-14 00:00", "明天全天")

    let p19 = QuickAddParser.parse("１１月２０日 提交", now: now)
    expectEqual(ymd(p19.due), "2026-11-20 00:00", "全角数字")

    let p20 = QuickAddParser.parse("下个月太远", now: now)
    expectEqual(p20.title, "下个月太远", "无关文本保持原样")

    let p22 = QuickAddParser.parse("晚上12点 跨年", now: now)
    expectEqual(ymd(p22.due), "2026-11-14 00:00", "晚上12点指午夜")
    let p23 = QuickAddParser.parse("今晚12点 睡觉", now: now)
    expectEqual(ymd(p23.due), "2026-11-14 00:00", "今晚12点指午夜")
    let p24 = QuickAddParser.parse("下午12点 吃饭", now: now)
    expectEqual(ymd(p24.due), "2026-11-13 12:00", "下午12点仍是中午")

    let p21 = QuickAddParser.parse("  明天   ", now: now)
    expectEqual(p21.title, "新日程", "标题兜底")
}

// MARK: - 分组与统计

func makeItems() -> [ScheduleItem] {
    [
        ScheduleItem(title: "过期任务", due: day(0, 9), priority: .high),
        ScheduleItem(title: "今天任务", due: day(0, 14)),
        ScheduleItem(title: "明天任务", due: day(1, 9), isAllDay: false),
        ScheduleItem(title: "远期任务", due: day(17, 9)),
        ScheduleItem(title: "已完成任务", due: day(-1, 9), isDone: true, completedAt: now)
    ]
}

func testSections() {
    let items = makeItems()

    let todaySections = ScheduleLogic.sections(items: items, filter: .today, now: now)
    let todayKinds = todaySections.map(\.kind)
    expect(todayKinds.contains(.overdue), "今天视图包含逾期")
    expectEqual(todaySections.filter { $0.kind == .day }.count, 1, "今天视图只有一个日期分组")
    expectEqual(todaySections.first { $0.kind == .day }?.items.count, 1, "今天分组条目数")
    expectEqual(todaySections.first { $0.kind == .day }?.title, "今天 · 11月13日 周五", "今天分组标题")

    let weekSections = ScheduleLogic.sections(items: items, filter: .week, now: now)
    let weekDays = weekSections.filter { $0.kind == .day }
    expectEqual(weekDays.count, 2, "7 天内包含今天和明天")
    expect(!weekSections.flatMap(\.items).contains { $0.title == "远期任务" }, "7 天内不含远期任务")

    let allSections = ScheduleLogic.sections(items: items, filter: .all, now: now)
    let allDays = allSections.filter { $0.kind == .day }
    expectEqual(allDays.count, 3, "全部视图包含三个日期分组")
    expectEqual(allSections.last?.kind, .done, "已完成在最后")
    expectEqual(allSections.last?.items.count, 1, "已完成条目数")

    let overdue = ScheduleLogic.overdueCount(items: items, now: now)
    expectEqual(overdue, 1, "逾期计数")
    expectEqual(ScheduleLogic.todayPendingCount(items: items, now: now), 2, "今日待办计数（含今天已逾期的）")
    expectEqual(ScheduleLogic.pendingCount(items: items), 4, "未完成计数")

    let next = ScheduleLogic.nextUpcoming(items: items, now: now)
    expectEqual(next?.title, "今天任务", "下一条日程")

    let summary = ScheduleLogic.statusSummary(items: items, now: now)
    expectEqual(summary.overdue, 1, "摘要逾期数")
    expectEqual(summary.todayPending, 2, "摘要今日数")

    let text = ScheduleLogic.menuBarText(items: items, now: now, mode: .next)
    expectEqual(text.text, "1 项逾期", "有逾期时菜单栏优先显示逾期")
    expect(text.alert, "逾期高亮")

    let cleanItems = items.filter { !$0.isOverdue(now: now) && $0.title != "过期任务" }
    let text2 = ScheduleLogic.menuBarText(items: cleanItems, now: now, mode: .next)
    expectEqual(text2.text, "14:00 今天任务", "菜单栏显示下一项")
    expect(!text2.alert, "无逾期不高亮")

    let text3 = ScheduleLogic.menuBarText(items: cleanItems, now: now, mode: .count)
    expectEqual(text3.text, "1", "菜单栏显示今日数量")

    let text4 = ScheduleLogic.menuBarText(items: cleanItems, now: now, mode: .iconOnly)
    expectEqual(text4.text, nil, "仅图标模式无文字")

    let empty = ScheduleLogic.menuBarText(items: [], now: now, mode: .next)
    expectEqual(empty.text, nil, "空列表无文字")

    // 明天条目的描述
    let tomorrow = cleanItems.first { $0.title == "明天任务" }!
    expectEqual(DateText.dueDescription(for: tomorrow, now: now), "明天 09:00", "明天时间描述")
    expectEqual(DateText.menuBarLabel(for: tomorrow, now: now), "明天 09:00 明天任务", "菜单栏标签")
    let allDay = ScheduleItem(title: "全天事项", due: day(0), isAllDay: true)
    expectEqual(DateText.dueDescription(for: allDay, now: now), "全天", "全天描述")
}

// MARK: - 「下周一」语义

func testNextWeekStartDay() {
    // 2026-11-13 是周五，下周一应为 11-16
    expectEqual(ymd(ScheduleLogic.nextWeekStartDay(forWeekday: 2, from: now)!), "2026-11-16 00:00", "周五看下周一")
    // 2026-11-16 是周一，下周一应为 11-23（而不是今天）
    let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 16))!
    expectEqual(ymd(ScheduleLogic.nextWeekStartDay(forWeekday: 2, from: monday)!), "2026-11-23 00:00", "周一看下周一")
    // 周五看下周日应为 11-22
    expectEqual(ymd(ScheduleLogic.nextWeekStartDay(forWeekday: 1, from: now)!), "2026-11-22 00:00", "周五看下周日")
}

// MARK: - 提醒时机

func testReminders() {
    let base = now // 2026-11-13 10:00
    var item = ScheduleItem(title: "开会", due: base.addingTimeInterval(10 * 60), reminderMinutes: 10)
    expectEqual(ScheduleLogic.remindersDue(items: [item], now: base).count, 1, "提前10分钟应提醒")

    item.notifiedFireKey = item.fireKey()
    expectEqual(ScheduleLogic.remindersDue(items: [item], now: base).count, 0, "已提醒过不重复")

    var old = ScheduleItem(title: "早上例会", due: base.addingTimeInterval(-60 * 60), reminderMinutes: 10)
    expectEqual(ScheduleLogic.remindersDue(items: [old], now: base).count, 0, "错过太久的定时提醒不再补弹")

    old.notifiedFireKey = nil
    old.due = base.addingTimeInterval(-15 * 60)
    expectEqual(ScheduleLogic.remindersDue(items: [old], now: base).count, 1, "错过 25 分钟内补弹")

    var noReminder = ScheduleItem(title: "读书", due: base.addingTimeInterval(5 * 60), reminderMinutes: nil)
    expectEqual(ScheduleLogic.remindersDue(items: [noReminder], now: base).count, 0, "未设置提醒不弹")
    noReminder.reminderMinutes = 5
    noReminder.isDone = true
    expectEqual(ScheduleLogic.remindersDue(items: [noReminder], now: base).count, 0, "已完成不提醒")

    // 全天日程当天 9:00 提醒，10:00 仍应补弹
    let allDay = ScheduleItem(title: "交房租", due: cal.startOfDay(for: base), isAllDay: true, reminderMinutes: 0)
    expectEqual(ScheduleLogic.remindersDue(items: [allDay], now: base).count, 1, "全天日程 9:00 提醒")

    // 稍后提醒：snooze 之后要等新时间
    var snoozed = ScheduleItem(title: "回电话", due: base.addingTimeInterval(60), reminderMinutes: 10)
    snoozed.snoozeUntil = base.addingTimeInterval(10 * 60)
    expectEqual(ScheduleLogic.remindersDue(items: [snoozed], now: base).count, 0, "稍后提醒期间不弹")
    expectEqual(ScheduleLogic.remindersDue(items: [snoozed], now: base.addingTimeInterval(11 * 60)).count, 1, "稍后提醒到点后弹")

    // 多条提醒按时间先后排序
    let first = ScheduleItem(title: "先", due: base.addingTimeInterval(2 * 60), reminderMinutes: 5)
    let second = ScheduleItem(title: "后", due: base.addingTimeInterval(5 * 60), reminderMinutes: 5)
    let ordered = ScheduleLogic.remindersDue(items: [second, first], now: base)
    expectEqual(ordered.first?.title, "先", "提醒按时间排序")
}

// MARK: - 数据仓库

func testStore() {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScheduleMemoTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let file = tmp.appendingPathComponent("schedules.json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    MainActor.assumeIsolated {
        let store = TaskStore(fileURL: file)
        expectEqual(store.items.count, 0, "初始为空")

        let added = store.add(title: "测试日程", due: day(0, 15), isAllDay: false, notes: "备注", priority: .high, reminderMinutes: 10)
        expectEqual(store.items.count, 1, "添加后数量")
        store.saveNow()

        let reloaded = TaskStore(fileURL: file)
        expectEqual(reloaded.items.count, 1, "重新加载数量")
        expectEqual(reloaded.items.first?.title, "测试日程", "重新加载标题")
        expectEqual(reloaded.items.first?.priority, .high, "重新加载优先级")
        expectEqual(reloaded.items.first?.reminderMinutes, 10, "重新加载提醒")

        var edited = store.item(with: added.id)!
        edited.title = "改名后的日程"
        edited.due = day(1, 9)
        store.update(edited)
        expectEqual(store.item(with: added.id)?.title, "改名后的日程", "修改标题")

        store.toggleDone(id: added.id)
        expectEqual(store.item(with: added.id)?.isDone, true, "标记完成")
        expect(store.item(with: added.id)?.completedAt != nil, "记录完成时间")
        store.toggleDone(id: added.id)
        expectEqual(store.item(with: added.id)?.isDone, false, "取消完成")

        store.snooze(id: added.id, minutes: 10, now: now)
        expect(store.item(with: added.id)?.effectiveReminderDate() != nil, "稍后提醒有效时间")

        store.delete(id: added.id)
        expectEqual(store.items.count, 0, "删除后数量")

        // 损坏数据恢复
        store.add(title: "需要恢复", due: day(0), isAllDay: true)
        store.saveNow()
        let backup = tmp.appendingPathComponent("schedules.backup.json")
        expect(FileManager.default.fileExists(atPath: backup.path), "备份文件已写入")
        try? "not json".data(using: .utf8)?.write(to: file)
        let recovered = TaskStore(fileURL: file)
        expectEqual(recovered.items.count, 1, "主文件损坏后从备份恢复")
        expectEqual(recovered.items.first?.title, "需要恢复", "恢复内容正确")
    }
}

// MARK: - 仓库边界行为

func testStoreEdgeCases() {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScheduleMemoEdge-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    let file = tmp.appendingPathComponent("schedules.json")
    defer { try? FileManager.default.removeItem(at: tmp) }

    MainActor.assumeIsolated {
        let store = TaskStore(fileURL: file)

        let item = store.add(title: "开会", due: day(0, 15), isAllDay: false)
        store.markNotified(id: item.id, key: "123")
        var edited = store.item(with: item.id)!
        edited.due = day(1, 9)
        store.update(edited)
        expect(store.item(with: item.id)?.notifiedFireKey == nil, "改时间后允许重新提醒")

        let allDay = store.add(title: "团建", due: day(1, 15, 30), isAllDay: true)
        let components = cal.dateComponents([.hour, .minute], from: store.item(with: allDay.id)!.due)
        expect(components.hour == 0 && components.minute == 0, "全天日程时间归零")

        store.toggleDone(id: allDay.id)
        store.deleteCompleted()
        expect(store.item(with: allDay.id) == nil, "清除已完成日程")
        expect(store.items.count == 1, "只删掉已完成的那条")
    }
}

// MARK: - 运行

testParser()
testSections()
testNextWeekStartDay()
testReminders()
testStore()
testStoreEdgeCases()

print("")
print("通过 \(passes) 项，失败 \(failures) 项")
exit(failures == 0 ? 0 : 1)