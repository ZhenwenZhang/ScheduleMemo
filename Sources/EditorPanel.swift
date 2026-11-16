import SwiftUI
import AppKit

// MARK: - 新建 / 编辑日程

struct EditorPanel: View {
    let mode: EditorMode
    let defaultReminderMinutes: Int?
    let onSave: (ScheduleItem) -> Void
    let onDelete: (ScheduleItem) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var notes: String
    @State private var datePart: Date
    @State private var timePart: Date
    @State private var isAllDay: Bool
    @State private var priority: TaskPriority
    @State private var reminderMinutes: Int?
    @State private var existingID: UUID?
    @State private var createdAt: Date
    @State private var confirmDelete = false
    @State private var confirmResetTask: Task<Void, Never>?

    @FocusState private var titleFocused: Bool

    init(
        mode: EditorMode,
        defaultReminderMinutes: Int?,
        onSave: @escaping (ScheduleItem) -> Void,
        onDelete: @escaping (ScheduleItem) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.defaultReminderMinutes = defaultReminderMinutes
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel

        switch mode {
        case .create:
            let now = Date()
            _title = State(initialValue: "")
            _notes = State(initialValue: "")
            _datePart = State(initialValue: ScheduleCalendar.work.startOfDay(for: now))
            _timePart = State(initialValue: now)
            _isAllDay = State(initialValue: true)
            _priority = State(initialValue: .medium)
            _reminderMinutes = State(initialValue: defaultReminderMinutes)
            _existingID = State(initialValue: nil)
            _createdAt = State(initialValue: now)
        case .edit(let item):
            _title = State(initialValue: item.title)
            _notes = State(initialValue: item.notes)
            _datePart = State(initialValue: item.due)
            _timePart = State(initialValue: item.due)
            _isAllDay = State(initialValue: item.isAllDay)
            _priority = State(initialValue: item.priority)
            _reminderMinutes = State(initialValue: item.reminderMinutes)
            _existingID = State(initialValue: item.id)
            _createdAt = State(initialValue: item.createdAt)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    titleField
                    dateTimeCard
                    priorityCard
                    notesCard
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 12)
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { titleFocused = true }
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
            Text(isEditing ? "编辑日程" : "新建日程")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            IconButton(systemName: "xmark", help: "关闭", size: 11) { onCancel() }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }

    // MARK: 标题

    private var titleField: some View {
        ZStack(alignment: .leading) {
            if title.isEmpty {
                Text("要做的事…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .allowsHitTesting(false)
            }
            TextField("", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .focused($titleFocused)
                .accessibilityLabel("日程标题")
                .padding(.horizontal, 12)
                .frame(height: 42)
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(titleFocused ? Color.accentColor.opacity(0.5) : Palette.hairline, lineWidth: 1)
        )
    }

    // MARK: 日期 / 时间 / 提醒

    private var dateTimeCard: some View {
        VStack(spacing: 0) {
            formRow("日期") {
                DatePicker("", selection: $datePart, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.small)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .accessibilityLabel("日期")
            }
            rowDivider
            formRow("快捷") {
                HStack(spacing: 4) {
                    shortcutChip("今天", offsetDays: 0)
                    shortcutChip("明天", offsetDays: 1)
                    shortcutChip("后天", offsetDays: 2)
                    shortcutChip("下周一", weekday: 2)
                }
            }
            rowDivider
            formRow("时间") {
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { !isAllDay },
                        set: { newValue in
                            if newValue {
                                applySuggestedTimeIfNeeded()
                            }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isAllDay = !newValue
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel("设定具体时间")
                    Text(isAllDay ? "全天" : "设定时刻")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !isAllDay {
                        DatePicker("", selection: $timePart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.stepperField)
                            .controlSize(.small)
                            .environment(\.locale, Locale(identifier: "zh_CN"))
                            .accessibilityLabel("时间")
                    }
                }
            }
            rowDivider
            formRow("提醒") {
                VStack(alignment: .trailing, spacing: 2) {
                    Picker("", selection: $reminderMinutes) {
                        ForEach(Array(AppSettings.reminderOptions.enumerated()), id: \.offset) { _, option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 120)
                    .accessibilityLabel("提醒")
                    if isAllDay && reminderMinutes != nil {
                        Text("全天日程在当天 9:00 提醒")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var rowDivider: some View {
        Divider().opacity(0.4).padding(.leading, 12)
    }

    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private func shortcutChip(_ text: String, offsetDays: Int? = nil, weekday: Int? = nil) -> some View {
        let target = chipTarget(offsetDays: offsetDays, weekday: weekday)
        let isSelected = target.map { ScheduleCalendar.work.isDate($0, inSameDayAs: datePart) } ?? false
        return Button {
            if let target {
                withAnimation(.easeOut(duration: 0.12)) { datePart = target }
            }
        } label: {
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 5)
                .frame(height: 20)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func chipTarget(offsetDays: Int?, weekday: Int?) -> Date? {
        let cal = ScheduleCalendar.work
        let today = cal.startOfDay(for: Date())
        if let offsetDays {
            return cal.date(byAdding: .day, value: offsetDays, to: today)
        }
        if let weekday {
            return ScheduleLogic.nextWeekStartDay(forWeekday: weekday, from: Date())
        }
        return nil
    }

    /// 切到「具体时刻」时，若当前还是 00:00，则给一个合理的默认时间
    private func applySuggestedTimeIfNeeded() {
        let cal = ScheduleCalendar.work
        let components = cal.dateComponents([.hour, .minute], from: timePart)
        guard components.hour == 0, components.minute == 0 else { return }
        let nextHour = cal.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        if cal.component(.hour, from: nextHour) == 0 {
            timePart = cal.date(bySettingHour: 9, minute: 0, second: 0, of: datePart) ?? nextHour
        } else {
            timePart = nextHour
        }
    }

    // MARK: 优先级

    private var priorityCard: some View {
        HStack(spacing: 10) {
            Text("优先级")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Picker("", selection: $priority) {
                ForEach(TaskPriority.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 126)
            .accessibilityLabel("优先级")
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .cardStyle()
    }

    // MARK: 备注

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("备注")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("可补充地点、准备材料等信息")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $notes)
                    .font(.system(size: 11))
                    .accessibilityLabel("备注")
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                    .frame(height: 64)
            }
        }
        .padding(10)
        .cardStyle()
    }

    // MARK: 底部按钮

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 8) {
                if isEditing {
                    Button {
                        if confirmDelete {
                            if let item = buildItem() { onDelete(item) }
                        } else {
                            confirmDelete = true
                            confirmResetTask?.cancel()
                            confirmResetTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                if !Task.isCancelled { confirmDelete = false }
                            }
                        }
                    } label: {
                        Text(confirmDelete ? "确认删除？" : "删除")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.high)
                            .padding(.horizontal, 10)
                            .frame(height: 27)
                            .background(
                                Capsule().fill(Palette.high.opacity(confirmDelete ? 0.16 : 0))
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Text("取消")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 27)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Button {
                    if let item = buildItem() { onSave(item) }
                } label: {
                    Text(isEditing ? "保存" : "添加")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 27)
                        .background(Capsule().fill(canSave ? Color.accentColor : Color.gray.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .help(canSave ? "保存日程（⌘↩）" : "先填写标题")
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 12)
            .frame(height: 51)
        }
    }

    // MARK: 组装

    private func combinedDue() -> Date {
        let cal = ScheduleCalendar.work
        let dayParts = cal.dateComponents([.year, .month, .day], from: datePart)
        guard !isAllDay else {
            return cal.startOfDay(for: datePart)
        }
        let timeParts = cal.dateComponents([.hour, .minute], from: timePart)
        var comps = DateComponents()
        comps.year = dayParts.year
        comps.month = dayParts.month
        comps.day = dayParts.day
        comps.hour = timeParts.hour
        comps.minute = timeParts.minute
        comps.second = 0
        return cal.date(from: comps) ?? datePart
    }

    private func buildItem() -> ScheduleItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var item = ScheduleItem(
            id: existingID ?? UUID(),
            title: trimmed,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            due: combinedDue(),
            isAllDay: isAllDay,
            priority: priority,
            isDone: false,
            reminderMinutes: reminderMinutes,
            createdAt: createdAt,
            updatedAt: Date()
        )

        if case .edit(let original) = mode {
            item.isDone = original.isDone
            item.completedAt = original.completedAt
            item.snoozeUntil = original.snoozeUntil
            item.notifiedFireKey = original.notifiedFireKey
        }
        return item
    }
}