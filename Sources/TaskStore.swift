import Foundation
import Combine

// MARK: - 持久化数据包装

private struct StoreEnvelope: Codable {
    var version: Int
    var items: [ScheduleItem]

    init(version: Int = 1, items: [ScheduleItem]) {
        self.version = version
        self.items = items
    }
}

// MARK: - 数据仓库

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var items: [ScheduleItem] = []
    @Published private(set) var loadError: String?

    let fileURL: URL
    private var pendingSave: DispatchWorkItem?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL = AppPaths.dataFile) {
        self.fileURL = fileURL
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        load()
    }

    // MARK: 读取

    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            items = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try decodeItems(from: data)
            loadError = nil
        } catch {
            // 主文件损坏时尝试备份
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("schedules.backup.json")
            if let data = try? Data(contentsOf: backup), let recovered = try? decodeItems(from: data) {
                items = recovered
                loadError = "主数据文件损坏，已从备份恢复"
                saveNow()
            } else {
                loadError = "数据读取失败：\(error.localizedDescription)"
                items = []
            }
        }
    }

    private func decodeItems(from data: Data) throws -> [ScheduleItem] {
        if let envelope = try? decoder.decode(StoreEnvelope.self, from: data) {
            return envelope.items
        }
        return try decoder.decode([ScheduleItem].self, from: data)
    }

    // MARK: 写入

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.saveNow() }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let envelope = StoreEnvelope(items: items)
            let data = try encoder.encode(envelope)
            try data.write(to: fileURL, options: .atomic)
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("schedules.backup.json")
            try? data.write(to: backup, options: .atomic)
            loadError = nil
        } catch {
            loadError = "保存失败：\(error.localizedDescription)"
        }
    }

    // MARK: CRUD

    @discardableResult
    func add(title: String, due: Date, isAllDay: Bool, notes: String = "", priority: TaskPriority = .medium, reminderMinutes: Int? = 10) -> ScheduleItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ScheduleItem(
            title: trimmed.isEmpty ? "新日程" : trimmed,
            notes: notes,
            due: isAllDay ? ScheduleCalendar.work.startOfDay(for: due) : due,
            isAllDay: isAllDay,
            priority: priority,
            reminderMinutes: reminderMinutes
        )
        items.append(item)
        sortItems()
        scheduleSave()
        return item
    }

    func insert(_ item: ScheduleItem) {
        var newItem = item
        newItem.updatedAt = Date()
        if newItem.isAllDay {
            newItem.due = ScheduleCalendar.work.startOfDay(for: newItem.due)
        }
        items.append(newItem)
        sortItems()
        scheduleSave()
    }

    func update(_ item: ScheduleItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = item
        if updated.isAllDay {
            updated.due = ScheduleCalendar.work.startOfDay(for: updated.due)
        }
        updated.updatedAt = Date()
        // 修改时间后允许重新提醒
        if items[index].due != updated.due || items[index].reminderMinutes != updated.reminderMinutes {
            updated.notifiedFireKey = nil
            updated.snoozeUntil = nil
        }
        if updated.isDone {
            if updated.completedAt == nil { updated.completedAt = Date() }
        } else {
            updated.completedAt = nil
        }
        items[index] = updated
        sortItems()
        scheduleSave()
    }

    func deleteCompleted() {
        items.removeAll { $0.isDone }
        scheduleSave()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    func toggleDone(id: UUID, now: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        items[index].updatedAt = now
        items[index].completedAt = items[index].isDone ? now : nil
        scheduleSave()
    }

    func markNotified(id: UUID, key: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].notifiedFireKey = key
        scheduleSave()
    }

    func snooze(id: UUID, minutes: Int, now: Date = Date()) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].snoozeUntil = now.addingTimeInterval(Double(minutes) * 60)
        items[index].notifiedFireKey = nil
        scheduleSave()
    }

    func clearSnooze(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].snoozeUntil = nil
    }

    func item(with id: UUID) -> ScheduleItem? {
        items.first { $0.id == id }
    }

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            return ScheduleLogic.itemSort(lhs: lhs, rhs: rhs)
        }
    }

    // MARK: 测试 / 演示数据

    func replaceAll(_ newItems: [ScheduleItem]) {
        items = newItems
        sortItems()
        saveNow()
    }

    func seedDemoIfRequested(now: Date = Date()) {
        guard ProcessInfo.processInfo.environment["SCHEDULEMEMO_SEED_DEMO"] == "1" else { return }
        let cal = ScheduleCalendar.work
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let base = cal.date(byAdding: .day, value: offset, to: today) ?? today
            return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        items = [
            ScheduleItem(title: "提交季度报告", notes: "把 Q4 数据补齐后发给张总", due: day(-1, 18, 0), isAllDay: false, priority: .high, reminderMinutes: 30),
            ScheduleItem(title: "项目周会", notes: "会议室 A，准备进度截图", due: day(0, 10, 30), isAllDay: false, priority: .high, reminderMinutes: 10),
            ScheduleItem(title: "整理本周待办", due: day(0, 14, 0), isAllDay: false, priority: .medium, reminderMinutes: 10),
            ScheduleItem(title: "买牛奶和面包", due: day(0, 0, 0), isAllDay: true, priority: .low, reminderMinutes: nil),
            ScheduleItem(title: "牙医复诊", notes: "带上病历本", due: day(1, 9, 0), isAllDay: false, priority: .medium, reminderMinutes: 30),
            ScheduleItem(title: "读书笔记：深度工作", due: day(2, 0, 0), isAllDay: true, priority: .low, reminderMinutes: nil),
            ScheduleItem(title: "提交报销单", due: day(4, 17, 0), isAllDay: false, priority: .medium, reminderMinutes: 60),
            ScheduleItem(title: "给妈妈打电话", due: day(-2, 20, 0), isAllDay: false, priority: .medium, isDone: true, reminderMinutes: nil, completedAt: now)
        ]
        sortItems()
        saveNow()
    }
}