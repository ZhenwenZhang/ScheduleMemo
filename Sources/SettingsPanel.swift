import SwiftUI
import AppKit

// MARK: - 设置

struct SettingsPanel: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: TaskStore
    var onClose: () -> Void
    var onOpenDataFolder: () -> Void

    @State private var confirmClear = false
    @State private var confirmResetTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    menuBarGroup
                    reminderGroup
                    generalGroup
                    dataGroup
                    aboutGroup
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { settings.refreshLaunchAtLoginStatus() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                    Text("返回").font(.system(size: 11.5))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("设置")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            // 占位保持标题居中
            Color.clear.frame(width: 48, height: 24)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }

    // MARK: 分组

    private var menuBarGroup: some View {
        groupCard(title: "菜单栏显示") {
            settingRow("显示内容") {
                Picker("", selection: $settings.menuBarMode) {
                    ForEach(MenuBarTextMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 118)
            }
            Divider().opacity(0.4).padding(.leading, 12)
            Text("有逾期日程时，菜单栏会优先显示「逾期数量」并用红色提示。")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var reminderGroup: some View {
        groupCard(title: "提醒") {
            settingRow("默认提前") {
                Picker("", selection: $settings.defaultReminderMinutes) {
                    ForEach(Array(AppSettings.reminderOptions.enumerated()), id: \.offset) { _, option in
                        Text(option.1).tag(option.0)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 118)
            }
            Divider().opacity(0.4).padding(.leading, 12)
            HStack(spacing: 8) {
                Text("提醒声音")
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: $settings.soundEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel("提醒声音")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            Divider().opacity(0.4).padding(.leading, 12)
            Text("到点后会从菜单栏下方弹出提醒卡片，可「完成」或「稍后提醒」。")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var generalGroup: some View {
        groupCard(title: "通用") {
            HStack(spacing: 8) {
                Text("开机自动启动")
                    .font(.system(size: 11.5))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            if let error = settings.loginItemError {
                Text(error)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.medium)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dataGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("数据")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("数据保存于本机，共 \(store.items.count) 条日程")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text(AppPaths.dataFile.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    smallButton("打开文件夹", systemImage: "folder") {
                        onOpenDataFolder()
                    }
                    smallButton("导出备份", systemImage: "square.and.arrow.down") {
                        exportBackup()
                    }
                    Spacer()
                }
                if store.items.contains(where: { $0.isDone }) {
                    smallButton(
                        confirmClear ? "确认清除？" : "清除已完成",
                        systemImage: "trash",
                        tint: Palette.high
                    ) {
                        if confirmClear {
                            store.deleteCompleted()
                            confirmClear = false
                        } else {
                            confirmClear = true
                            confirmResetTask?.cancel()
                            confirmResetTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                if !Task.isCancelled { confirmClear = false }
                            }
                        }
                    }
                }
            }
            .padding(10)
            .cardStyle()
        }
    }

    private var aboutGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("关于")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentColor)
                    Text("日程备忘录 \(AppInfo.version)")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                }
                Text("快捷键：回车 快速添加 · ⌘N 新建日程 · 点按条目编辑")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("右键菜单栏图标可查看今日概况、打开设置或退出。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .cardStyle()
        }
    }

    // MARK: 组件

    private func groupCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .cardStyle()
        }
    }

    private func settingRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11.5))
            Spacer(minLength: 6)
            content()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
    }

    private func smallButton(_ title: String, systemImage: String, tint: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 9.5))
                Text(title).font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "schedules-backup.json"
        panel.allowedContentTypes = [.json]
        panel.title = "导出日程备份"
        if panel.runModal() == .OK, let url = panel.url {
            store.saveNow()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.copyItem(at: AppPaths.dataFile, to: url)
        }
    }
}

// MARK: - 版本信息

enum AppInfo {
    static let bundleIdentifier = "com.zhenwenzhang.schedulememo"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }
}