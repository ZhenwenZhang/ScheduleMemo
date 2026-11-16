import SwiftUI
import Combine
import AppKit

// MARK: - 编辑器状态

enum EditorMode: Identifiable {
    case create
    case edit(ScheduleItem)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let item): return item.id.uuidString
        }
    }
}

// MARK: - 提示条

private struct ToastMessage: Identifiable {
    let id = UUID()
    let text: String
    var actionLabel: String?
    var action: (() -> Void)?
}

// MARK: - 主面板

struct PopoverView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var layout: PopoverLayout
    @ObservedObject var bus: CommandBus
    var onQuit: () -> Void
    var onDismiss: () -> Void
    var onOpenDataFolder: () -> Void

    @State private var filter: ListFilter = .today
    @State private var quickText = ""
    @State private var editorMode: EditorMode?
    @State private var showSettings = false
    @State private var showDone = false
    @State private var now = Date()
    @State private var toast: ToastMessage?
    @State private var toastTask: Task<Void, Never>?
    @FocusState private var quickFocused: Bool

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // MARK: 派生数据

    private var allSections: [ItemSection] {
        ScheduleLogic.sections(items: store.items, filter: filter, now: now)
    }
    private var daySections: [ItemSection] { allSections.filter { $0.kind != .done } }
    private var doneSection: ItemSection? { allSections.first { $0.kind == .done } }
    private var pendingCount: Int { ScheduleLogic.pendingCount(items: store.items) }
    private var todayCount: Int { ScheduleLogic.todayPendingCount(items: store.items, now: now) }
    private var overdueCount: Int { ScheduleLogic.overdueCount(items: store.items, now: now) }

    private var listHeight: CGFloat {
        if daySections.isEmpty && doneSection == nil { return 170 }
        var height: CGFloat = 0
        for section in daySections {
            height += 22 + CGFloat(section.items.count) * 46 + 12
        }
        if let done = doneSection {
            height += 26
            if showDone { height += CGFloat(done.items.count) * 46 + 8 }
        }
        return min(352, max(110, height + 10))
    }

    private var overlayHeight: CGFloat {
        showSettings ? PopoverLayout.settingsHeight : PopoverLayout.editorHeight
    }

    private var naturalHeight: CGFloat {
        if showSettings || editorMode != nil { return overlayHeight }
        let warning: CGFloat = store.loadError == nil ? 0 : 24
        return 56 + 42 + 32 + 1 + listHeight + 41 + warning
    }

    private var summaryText: String {
        if overdueCount > 0 { return "未完成 \(pendingCount) · 逾期 \(overdueCount)" }
        if todayCount > 0 { return "未完成 \(pendingCount) · 今天 \(todayCount)" }
        return "未完成 \(pendingCount) 项"
    }

    private var quickPreview: String? {
        let trimmed = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parsed = QuickAddParser.parse(trimmed, now: now)
        let day = DateText.relativeDay(parsed.due, now: now)
        if parsed.isAllDay { return day }
        return "\(day) \(DateText.time.string(from: parsed.due))"
    }

    // MARK: 视图

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainPanel

            if showSettings {
                SettingsPanel(
                    settings: settings,
                    store: store,
                    onClose: { closeSettings() },
                    onOpenDataFolder: onOpenDataFolder
                )
                .frame(width: PopoverLayout.width, height: PopoverLayout.settingsHeight)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
            }

            if let mode = editorMode {
                EditorPanel(
                    mode: mode,
                    defaultReminderMinutes: settings.defaultReminderMinutes,
                    onSave: { item in saveEditor(item, mode: mode) },
                    onDelete: { item in deleteFromEditor(item) },
                    onCancel: { closeEditor() }
                )
                .frame(width: PopoverLayout.width, height: PopoverLayout.editorHeight)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(3)
            }

            if let toast = toast {
                toastView(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        .frame(width: PopoverLayout.width, height: naturalHeight)
        .onReceive(ticker) { now = $0 }
        .onAppear {
            now = Date()
            if let raw = ProcessInfo.processInfo.environment["SCHEDULEMEMO_INITIAL_FILTER"],
               let initialFilter = ListFilter(rawValue: raw) {
                filter = initialFilter
            }
            layout.height = naturalHeight
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { quickFocused = true }
        }
        .onChange(of: naturalHeight) { _, newValue in
            withAnimation(.easeInOut(duration: 0.16)) { layout.height = newValue }
        }
        .onChange(of: bus.createRequest) { _, _ in
            openEditor(.create)
        }
        .onChange(of: bus.settingsRequest) { _, _ in
            withAnimation(.easeInOut(duration: 0.18)) { showSettings = true }
        }
        .onChange(of: bus.escapeRequest) { _, _ in
            if editorMode != nil {
                closeEditor()
            } else if showSettings {
                closeSettings()
            } else {
                onDismiss()
            }
        }
    }

    private func dataWarning(_ message: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Palette.medium)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            headerView
                .frame(height: 56)
            if let error = store.loadError {
                dataWarning(error)
                    .frame(height: 24)
            }
            quickAddView
                .frame(height: 42)
            filterBar
                .frame(height: 32)
            Divider().opacity(0.5)
            listContent
                .frame(height: listHeight)
            footerView
                .frame(height: 40)
        }
        .frame(width: PopoverLayout.width)
    }

    // MARK: 顶部

    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("日程备忘录")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(DateText.headerDate(now))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                openEditor(.create)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                    Text("新建").font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 25)
                .background(Capsule().fill(Color.accentColor))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("新建日程（⌘N）")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    // MARK: 快捷添加

    private var quickAddView: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            TextField("添加日程…", text: $quickText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($quickFocused)
                .onSubmit { submitQuickAdd() }
            if let preview = quickPreview {
                Text(preview)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            if !quickText.isEmpty {
                IconButton(systemName: "xmark.circle.fill", help: "清空", size: 10) {
                    quickText = ""
                    quickFocused = true
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(quickFocused ? Color.accentColor.opacity(0.55) : Palette.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: 筛选

    private var filterBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $filter) {
                ForEach(ListFilter.allCases) { f in
                    Text(f.label).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: 列表

    private var listContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12) {
                if daySections.isEmpty && doneSection == nil {
                    emptyState
                } else {
                    if daySections.isEmpty {
                        allDoneState
                    }
                    ForEach(daySections) { section in
                        sectionView(section)
                    }
                    if let done = doneSection {
                        doneView(done)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 9)
            .padding(.bottom, 9)
        }
    }

    private func sectionView(_ section: ItemSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if section.kind == .overdue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.high)
                }
                Text(section.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(section.kind == .overdue ? Palette.high : Color.secondary)
                Spacer()
                Text("\(section.items.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider()
                            .opacity(0.35)
                            .padding(.leading, 43)
                    }
                    ScheduleRowView(
                        item: item,
                        now: now,
                        onToggle: { toggle(item) },
                        onEdit: { openEditor(.edit(current(item))) },
                        onDelete: { delete(item) },
                        onSnooze: { store.snooze(id: item.id, minutes: $0) }
                    )
                }
            }
            .cardStyle()
        }
    }

    private func doneView(_ section: ItemSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { showDone.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(showDone ? 90 : 0))
                        .foregroundStyle(.tertiary)
                    Text("已完成")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(section.items.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if showDone {
                VStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().opacity(0.35).padding(.leading, 43)
                        }
                        ScheduleRowView(
                            item: item,
                            now: now,
                            onToggle: { toggle(item) },
                            onEdit: { openEditor(.edit(current(item))) },
                            onDelete: { delete(item) },
                            onSnooze: { store.snooze(id: item.id, minutes: $0) }
                        )
                    }
                }
                .cardStyle()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 46, height: 46)
                Image(systemName: filter == .today ? "calendar.badge.checkmark" : "tray")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            Text(emptyTitle)
                .font(.system(size: 12.5, weight: .medium))
            Text(emptySubtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 190)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
    }

    private var allDoneState: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.green)
            Text(filter == .today ? "今天的日程都完成啦" : "当前筛选下没有待办")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var emptyTitle: String {
        switch filter {
        case .today: return "今天暂无安排"
        case .week: return "未来 7 天暂无安排"
        case .all: return "还没有日程"
        }
    }

    private var emptySubtitle: String {
        switch filter {
        case .today: return "在上方输入框里写「明天 10:00 交报告」，回车即可添加"
        case .week: return "留点空白也很好，需要时按 ⌘N 新建"
        case .all: return "点击右上角「新建」，或在上方输入框快速添加"
        }
    }

    // MARK: 底部

    private var footerView: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 4) {
                Text(summaryText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                IconButton(systemName: "gearshape", help: "设置", size: 11) {
                    withAnimation(.easeInOut(duration: 0.18)) { showSettings = true }
                }
                IconButton(systemName: "power", help: "退出日程备忘录", size: 11) {
                    onQuit()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 39)
        }
    }

    private func toastView(_ toast: ToastMessage) -> some View {
        HStack(spacing: 7) {
            Image(systemName: toast.actionLabel == nil ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(toast.actionLabel == nil ? Color.green : Color.accentColor)
            Text(toast.text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            if let label = toast.actionLabel, let action = toast.action {
                Button {
                    action()
                    self.toast = nil
                } label: {
                    Text(label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.97))
        )
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: 行为

    private func current(_ item: ScheduleItem) -> ScheduleItem {
        store.item(with: item.id) ?? item
    }

    private func toggle(_ item: ScheduleItem) {
        let willComplete = !item.isDone
        withAnimation(.easeInOut(duration: 0.2)) {
            store.toggleDone(id: item.id)
        }
        now = Date()
        guard willComplete else { return }
        let title = DateText.shorten(item.title, limit: 12)
        flashToast("已完成「\(title)」", actionLabel: "撤销", action: { [store] in
            store.toggleDone(id: item.id)
        }, duration: 3.5)
    }

    private func delete(_ item: ScheduleItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.delete(id: item.id)
        }
        undoableDelete(item)
    }

    private func undoableDelete(_ item: ScheduleItem) {
        let title = DateText.shorten(item.title, limit: 12)
        flashToast("已删除「\(title)」", actionLabel: "撤销", action: { [store] in
            store.insert(item)
        }, duration: 4)
    }

    private func submitQuickAdd() {
        let text = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let parsed = QuickAddParser.parse(text, now: Date())
        let item = ScheduleItem(
            title: parsed.title,
            due: parsed.due,
            isAllDay: parsed.isAllDay,
            priority: .medium,
            reminderMinutes: settings.defaultReminderMinutes
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            store.insert(item)
        }
        quickText = ""
        quickFocused = true
        now = Date()

        let day = DateText.relativeDay(parsed.due, now: now)
        let desc = parsed.isAllDay ? day : "\(day) \(DateText.time.string(from: parsed.due))"
        flashToast("已添加「\(DateText.shorten(parsed.title, limit: 14))」· \(desc)")
        ensureVisible(due: parsed.due)
    }

    private func openEditor(_ mode: EditorMode) {
        quickFocused = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            editorMode = mode
        }
    }

    private func closeEditor() {
        withAnimation(.easeOut(duration: 0.2)) {
            editorMode = nil
        }
        now = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { quickFocused = true }
    }

    private func saveEditor(_ item: ScheduleItem, mode: EditorMode) {
        switch mode {
        case .create:
            withAnimation(.easeInOut(duration: 0.2)) {
                store.insert(item)
            }
            flashToast("已创建「\(DateText.shorten(item.title, limit: 14))」")
            ensureVisible(due: item.due)
        case .edit:
            store.update(item)
            flashToast("已更新「\(DateText.shorten(item.title, limit: 14))」")
            ensureVisible(due: item.due)
        }
        closeEditor()
    }

    private func deleteFromEditor(_ item: ScheduleItem) {
        store.delete(id: item.id)
        closeEditor()
        undoableDelete(item)
    }

    /// 新增/修改后，如果当前筛选看不到这条日程，自动切到更宽的筛选
    private func ensureVisible(due: Date) {
        let calendar = ScheduleCalendar.work
        let today = calendar.startOfDay(for: Date())
        let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: due)).day ?? 0
        guard offset > 0 else { return }
        if filter == .today { filter = offset > 6 ? .all : .week }
        else if filter == .week && offset > 6 { filter = .all }
    }

    private func closeSettings() {
        withAnimation(.easeOut(duration: 0.18)) {
            showSettings = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { quickFocused = true }
    }

    private func flashToast(
        _ text: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil,
        duration: TimeInterval = 2.2
    ) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toast = ToastMessage(text: text, actionLabel: actionLabel, action: action)
        }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { toast = nil }
        }
    }
}

// MARK: - 单行日程

struct ScheduleRowView: View {
    let item: ScheduleItem
    let now: Date
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSnooze: (Int) -> Void

    @State private var hovering = false

    private var overdue: Bool { item.isOverdue(now: now) }

    private var meta: (text: String, alert: Bool) {
        if overdue {
            if item.isAllDay {
                return ("已逾期 · \(DateText.monthDay.string(from: item.due))", true)
            }
            return ("已逾期 · \(DateText.time.string(from: item.due))", true)
        }
        return (DateText.dueDescription(for: item, now: now), false)
    }

    var body: some View {
        HStack(spacing: 9) {
            CircleCheck(isDone: item.isDone, action: onToggle)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if item.priority == .high && !item.isDone {
                        Image(systemName: "exclamationmark.2")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Palette.high)
                    }
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .strikethrough(item.isDone, color: .secondary)
                        .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    if !item.notes.isEmpty {
                        Image(systemName: "note.text")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: item.isAllDay ? "calendar" : "clock")
                        .font(.system(size: 8.5))
                    Text(meta.text)
                        .font(.system(size: 10))
                    if item.reminderMinutes != nil && !item.isDone {
                        Image(systemName: "bell")
                            .font(.system(size: 8))
                    }
                }
                .foregroundStyle(meta.alert ? Palette.high : Color.secondary)
            }

            Spacer(minLength: 2)

            if hovering && !item.isDone {
                HStack(spacing: 0) {
                    IconButton(systemName: "pencil", help: "编辑", size: 10, action: onEdit)
                    IconButton(systemName: "trash", help: "删除", size: 10, action: onDelete)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(Color.primary.opacity(hovering ? 0.045 : 0))
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
        .onTapGesture { onEdit() }
        .help(item.notes.isEmpty ? "\(item.title) · \(meta.text)" : "\(item.title)\n\(item.notes)")
        .contextMenu {
            Button(item.isDone ? "标记为未完成" : "标记为完成", action: onToggle)
            Button("编辑…", action: onEdit)
            if !item.isDone && item.reminderMinutes != nil {
                Menu("稍后提醒") {
                    Button("10 分钟后") { onSnooze(10) }
                    Button("30 分钟后") { onSnooze(30) }
                    Button("1 小时后") { onSnooze(60) }
                }
            }
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}