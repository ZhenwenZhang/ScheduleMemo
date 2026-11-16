import Foundation

/// 快捷添加时从自然语言里解析日期与时间。
/// 支持示例：
///   「明天 10:00 交报告」 「今天下午3点 开会」 「周五 上午9点半 复盘」
///   「11月20日 提交材料」 「3天后 取快递」 「下周一 9点 晨会」 「买牛奶」
enum QuickAddParser {
    struct Result: Equatable {
        var title: String
        var due: Date
        var isAllDay: Bool
        var matchedDate: Bool
        var matchedTime: Bool
    }

    private enum Period {
        case dawn, morning, am, noon, pm, dusk, night, deepNight

        var defaultHour: Int {
            switch self {
            case .dawn: return 5
            case .morning: return 7
            case .am: return 10
            case .noon: return 12
            case .pm: return 15
            case .dusk: return 18
            case .night: return 20
            case .deepNight: return 23
            }
        }
    }

    // MARK: - 入口

    static func parse(
        _ raw: String,
        now: Date = Date(),
        calendar: Calendar = ScheduleCalendar.work
    ) -> Result {
        let normalized = normalize(raw)
        let ns = normalized as NSString
        var marked: [NSRange] = []

        var dueDay: Date?
        var matchedDate = false
        var hour: Int?
        var minute = 0
        var period: Period?
        var matchedTime = false
        var matchedWeekday = false
        var forcedAllDay = false

        func overlaps(_ range: NSRange) -> Bool {
            marked.contains { NSIntersectionRange($0, range).length > 0 }
        }

        func mark(_ range: NSRange) {
            guard range.location != NSNotFound, range.length > 0, !overlaps(range) else { return }
            marked.append(range)
        }

        func addWord(_ word: String) -> Bool {
            var searchStart = 0
            while searchStart < ns.length {
                let found = ns.range(of: word, options: [], range: NSRange(location: searchStart, length: ns.length - searchStart))
                guard found.location != NSNotFound else { return false }
                if !overlaps(found) {
                    mark(found)
                    return true
                }
                searchStart = found.location + max(1, found.length)
            }
            return false
        }

        func firstMatch(_ pattern: String) -> NSTextCheckingResult? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let all = regex.matches(in: ns as String, range: NSRange(location: 0, length: ns.length))
            return all.first { !overlaps($0.range) }
        }

        let cal = calendar
        let today = cal.startOfDay(for: now)

        // 1. 绝对日期：2026-12-01、2026/12/01、2026年12月1日
        if let m = firstMatch("(?<!\\d)(\\d{4})[-/.年](\\d{1,2})[-/.月](\\d{1,2})(?:日|号)?(?!\\d)") {
            if let yText = m.group(1, in: ns), let moText = m.group(2, in: ns), let dText = m.group(3, in: ns),
               let y = Int(yText), let mo = Int(moText), let d = Int(dText),
               let date = makeDate(year: y, month: mo, day: d, calendar: cal) {
                dueDay = date
                matchedDate = true
                mark(m.range)
            }
        }

        // 2. 月日：11月20日 / 11月20号
        if dueDay == nil, let m = firstMatch("(?<!\\d)(\\d{1,2})月(\\d{1,2})(?:日|号)?(?!\\d)") {
            if let moText = m.group(1, in: ns), let dText = m.group(2, in: ns),
               let mo = Int(moText), let d = Int(dText),
               var date = makeDate(year: nil, month: mo, day: d, calendar: cal) {
                if date < today { date = cal.date(byAdding: .year, value: 1, to: date) ?? date }
                dueDay = cal.startOfDay(for: date)
                matchedDate = true
                mark(m.range)
            }
        }

        // 3. 斜杠日期：12/25
        if dueDay == nil, let m = firstMatch("(?<![\\d/])(\\d{1,2})/(\\d{1,2})(?![\\d/])") {
            if let moText = m.group(1, in: ns), let dText = m.group(2, in: ns),
               let mo = Int(moText), let d = Int(dText),
               var date = makeDate(year: nil, month: mo, day: d, calendar: cal) {
                if date < today { date = cal.date(byAdding: .year, value: 1, to: date) ?? date }
                dueDay = cal.startOfDay(for: date)
                matchedDate = true
                mark(m.range)
            }
        }

        // 4. 只有几号：20号
        if dueDay == nil, let m = firstMatch("(?<![\\d月])(\\d{1,2})(?:日|号)(?![\\d月])") {
            if let d = m.group(1, in: ns), let dayNum = Int(d) {
                let comps = cal.dateComponents([.year, .month, .day], from: today)
                let curMonth = comps.month ?? 1
                let curDay = comps.day ?? 1
                let targetMonth = dayNum < curDay ? (curMonth % 12) + 1 : curMonth
                let yearOffset = (curMonth == 12 && dayNum < curDay) ? 1 : 0
                if let date = makeDate(year: (comps.year ?? 2026) + yearOffset, month: targetMonth, day: dayNum, calendar: cal) {
                    dueDay = cal.startOfDay(for: date)
                    matchedDate = true
                    mark(m.range)
                }
            }
        }

        // 5. 相对日期词
        if dueDay == nil {
            let relativeWords: [(String, Int)] = [
                ("大后天", 3), ("后天", 2), ("明天", 1), ("明日", 1), ("今天", 0), ("今日", 0)
            ]
            for (word, offset) in relativeWords where dueDay == nil {
                if addWord(word) {
                    dueDay = cal.date(byAdding: .day, value: offset, to: today)
                    matchedDate = true
                }
            }
        }

        // 6. 明晚 / 今晚 / 明早 / 今早
        if dueDay == nil {
            let combos: [(String, Int, Period)] = [
                ("明晚", 1, .night), ("明早", 1, .morning),
                ("今晚", 0, .night), ("今早", 0, .morning)
            ]
            for (word, offset, p) in combos where dueDay == nil {
                if addWord(word) {
                    dueDay = cal.date(byAdding: .day, value: offset, to: today)
                    matchedDate = true
                    if period == nil { period = p }
                }
            }
        }

        // 7. 下周X / 周X / 星期X / 礼拜X
        if dueDay == nil {
            let weekdayMap: [Character: Int] = ["一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7, "日": 1, "天": 1]
            if let m = firstMatch("下周([一二三四五六日天])"), let ch = m.group(1, in: ns)?.first, let weekday = weekdayMap[ch] {
                if let date = nextWeekday(weekday, after: today, forceNextWeek: true, calendar: cal) {
                    dueDay = date
                    matchedDate = true
                    matchedWeekday = true
                    mark(m.range)
                }
            }
            if dueDay == nil, let m = firstMatch("(?:周|星期|礼拜)([一二三四五六日天])"), let ch = m.group(1, in: ns)?.first, let weekday = weekdayMap[ch] {
                if let date = nextWeekday(weekday, after: today, forceNextWeek: false, calendar: cal) {
                    dueDay = date
                    matchedDate = true
                    matchedWeekday = true
                    mark(m.range)
                }
            }
        }

        // 8. N 天后 / N 周后
        if dueDay == nil, let m = firstMatch("(?<!\\d)(\\d{1,3})(天|周)(?:之)?后") {
            if let n = m.group(1, in: ns), let num = Int(n), let unit = m.group(2, in: ns) {
                let days = unit == "周" ? num * 7 : num
                dueDay = cal.date(byAdding: .day, value: days, to: today)
                matchedDate = true
                mark(m.range)
            }
        }

        // 9. 具体时间：10:30 / 9点 / 9点半 / 9点30分
        if let m = firstMatch("(?<!\\d)(\\d{1,2})[:：](\\d{2})(?!\\d)") {
            if let h = m.group(1, in: ns), let mm = m.group(2, in: ns), let hh = Int(h), let mmm = Int(mm), (0...23).contains(hh), (0...59).contains(mmm) {
                hour = hh
                minute = mmm
                matchedTime = true
                mark(m.range)
            }
        }
        if hour == nil, let m = firstMatch("(?<!\\d)(\\d{1,2})[点時时](?:(半)|(\\d{1,2})分?)?") {
            if let h = m.group(1, in: ns), let hh = Int(h), (0...23).contains(hh) {
                hour = hh
                if m.group(2, in: ns) != nil {
                    minute = 30
                } else if let mm = m.group(3, in: ns), let mmm = Int(mm), (0...59).contains(mmm) {
                    minute = mmm
                } else {
                    minute = 0
                }
                matchedTime = true
                mark(m.range)
            }
        }

        // 10. 时段词
        if period == nil {
            let periods: [(String, Period)] = [
                ("凌晨", .dawn), ("清晨", .morning), ("早上", .morning), ("早晨", .morning),
                ("上午", .am), ("中午", .noon), ("下午", .pm), ("傍晚", .dusk),
                ("晚上", .night), ("夜里", .night), ("深夜", .deepNight)
            ]
            for (word, p) in periods {
                if addWord(word) {
                    period = p
                    matchedTime = true
                    break
                }
            }
        }

        // 11. 全天
        if addWord("全天") {
            forcedAllDay = true
        }

        // MARK: 汇总时间

        var finalHour = hour
        if let h = hour {
            finalHour = resolveHour(h, period: period)
        } else if let p = period {
            finalHour = p.defaultHour
        }

        var due: Date
        var isAllDay: Bool

        if let h = finalHour, !forcedAllDay {
            var baseDay = dueDay ?? today
            // 「今晚 12 点」「晚上 12 点」指次日 00:00
            if (period == .night || period == .deepNight), h == 0 {
                baseDay = cal.date(byAdding: .day, value: 1, to: baseDay) ?? baseDay
            }
            minute = max(0, min(59, minute))
            var comps = cal.dateComponents([.year, .month, .day], from: baseDay)
            comps.hour = h
            comps.minute = minute
            comps.second = 0
            var date = cal.date(from: comps) ?? baseDay
            if dueDay == nil && date < now {
                // 只说了时间但已过点：理解为明天
                date = cal.date(byAdding: .day, value: 1, to: date) ?? date
                baseDay = cal.startOfDay(for: date)
            }
            if matchedWeekday, let day = dueDay, cal.isDate(day, inSameDayAs: today), date < now {
                // 只说「周五」且今天就是周五、时间已过：理解为下周五
                date = cal.date(byAdding: .day, value: 7, to: date) ?? date
            }
            due = date
            isAllDay = false
            matchedTime = true
        } else {
            let day = dueDay ?? today
            due = cal.startOfDay(for: day)
            isAllDay = true
        }

        // MARK: 标题

        var title = removeRanges(marked, from: normalized)
        title = cleanTitle(title)
        if title.isEmpty {
            title = "新日程"
        }

        return Result(title: title, due: due, isAllDay: isAllDay, matchedDate: matchedDate, matchedTime: matchedTime)
    }

    // MARK: - 辅助

    private static func normalize(_ text: String) -> String {
        var result = text
        let asciiMap: [Character: Character] = [
            "０": "0", "１": "1", "２": "2", "３": "3", "４": "4",
            "５": "5", "６": "6", "７": "7", "８": "8", "９": "9",
            "：": ":", "　": " "
        ]
        result = String(result.map { asciiMap[$0] ?? $0 })
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveHour(_ hour: Int, period: Period?) -> Int {
        guard let period = period else {
            if hour >= 13 { return hour }
            if hour == 12 { return 12 }
            if hour >= 7 { return hour }
            return hour + 12
        }
        switch period {
        case .dawn:
            return hour == 12 ? 0 : (hour >= 12 ? hour - 12 : hour)
        case .morning, .am:
            return hour == 12 ? 0 : (hour >= 12 ? hour % 12 : hour)
        case .noon:
            return hour == 12 ? 12 : (hour < 12 ? hour + 12 : hour)
        case .pm, .dusk:
            return hour < 12 ? hour + 12 : hour
        case .night, .deepNight:
            // 晚上 12 点即午夜
            if hour == 12 { return 0 }
            return hour < 12 ? hour + 12 : hour
        }
    }

    private static func makeDate(year: Int?, month: Int, day: Int, calendar: Calendar) -> Date? {
        var comps = DateComponents()
        comps.year = year ?? calendar.component(.year, from: Date())
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        guard let date = calendar.date(from: comps) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == comps.year, check.month == comps.month, check.day == comps.day else { return nil }
        return calendar.startOfDay(for: date)
    }

    private static func nextWeekday(_ weekday: Int, after today: Date, forceNextWeek: Bool, calendar: Calendar) -> Date? {
        var candidate: Date?
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            if calendar.component(.weekday, from: day) == weekday {
                candidate = day
                break
            }
        }
        guard var date = candidate else { return nil }
        if forceNextWeek,
           let weekEnd = calendar.dateInterval(of: .weekOfYear, for: today)?.end,
           date < weekEnd {
            date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
        }
        return calendar.startOfDay(for: date)
    }

    private static func removeRanges(_ ranges: [NSRange], from text: String) -> String {
        let mutable = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            guard range.location + range.length <= mutable.length else { continue }
            mutable.deleteCharacters(in: range)
        }
        return mutable as String
    }

    private static func cleanTitle(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "[\\s　]+") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: " ")
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: "，,、;；:：-—–·|/")
        result = result.trimmingCharacters(in: separators)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        // 去掉开头多余的「在」
        if result.hasPrefix("在"), result.count > 1 {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}

private extension NSTextCheckingResult {
    func group(_ index: Int, in ns: NSString) -> String? {
        guard numberOfRanges > index else { return nil }
        let range = self.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }
}