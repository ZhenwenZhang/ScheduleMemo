import AppKit
import SwiftUI

// MARK: - 到点提醒

@MainActor
final class ReminderCenter {
    private let store: TaskStore
    private let settings: AppSettings
    private let isPopoverVisible: () -> Bool

    private var timer: Timer?
    private var panel: ReminderPanel?
    private var autoDismissTask: Task<Void, Never>?

    init(store: TaskStore, settings: AppSettings, isPopoverVisible: @escaping () -> Bool) {
        self.store = store
        self.settings = settings
        self.isPopoverVisible = isPopoverVisible
    }

    func start() {
        checkDue()
        let timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func checkDue(now: Date = Date()) {
        guard panel == nil else { return }
        guard !isPopoverVisible() else { return }

        let calendar = ScheduleCalendar.work
        guard let first = ScheduleLogic.remindersDue(items: store.items, now: now, calendar: calendar).first else { return }
        store.markNotified(id: first.id, key: first.fireKey(calendar: calendar))
        present(first)
    }

    func presentDemo() {
        let demo = ScheduleItem(
            title: "项目周会",
            notes: "会议室 A，准备进度截图",
            due: Date().addingTimeInterval(10 * 60),
            isAllDay: false,
            priority: .high,
            reminderMinutes: 10
        )
        present(demo)
    }

    private func present(_ item: ScheduleItem) {
        autoDismissTask?.cancel()
        panel?.close()

        let now = Date()
        let dueText: String
        if item.isAllDay {
            dueText = "全天 · " + DateText.relativeDay(item.due, now: now)
        } else {
            dueText = DateText.relativeDay(item.due, now: now) + " " + DateText.time.string(from: item.due)
        }

        let card = ReminderCardView(
            title: item.title,
            dueText: dueText,
            notes: item.notes,
            onDone: { [weak self] in self?.complete(item) },
            onSnooze: { [weak self] in self?.snooze(item) },
            onClose: { [weak self] in self?.dismiss() }
        )

        let hosting = NSHostingView(rootView: card)
        hosting.layoutSubtreeIfNeeded()
        let width: CGFloat = 336
        let size = NSSize(width: width, height: max(120, hosting.fittingSize.height))

        let panel = ReminderPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.contentView = hosting
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.maxX - size.width - 14
            let y = visible.maxY - size.height - 10
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        if settings.soundEnabled {
            NSSound(named: "Tink")?.play()
        }

        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func complete(_ item: ScheduleItem) {
        if let current = store.item(with: item.id), !current.isDone {
            store.toggleDone(id: item.id)
        }
        dismiss()
    }

    private func snooze(_ item: ScheduleItem) {
        store.snooze(id: item.id, minutes: 10)
        dismiss()
    }

    private func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        panel?.close()
        panel = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkDue()
        }
    }
}

// MARK: - 提醒浮窗

final class ReminderPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct ReminderCardView: View {
    let title: String
    let dueText: String
    let notes: String
    let onDone: () -> Void
    let onSnooze: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(Palette.high.opacity(0.14)).frame(width: 22, height: 22)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.high)
                }
                Text("日程提醒")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                IconButton(systemName: "xmark", help: "关闭提醒", size: 9, action: onClose)
            }

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 9))
                Text(dueText).font(.system(size: 10.5))
            }
            .foregroundStyle(.secondary)

            if !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button(action: onDone) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        Text("完成").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 25)
                    .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)

                Button(action: onSnooze) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 9))
                        Text("10 分钟后").font(.system(size: 10.5))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 25)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 1)
        }
        .padding(14)
        .frame(width: 336)
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow, cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}