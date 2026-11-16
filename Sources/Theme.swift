import SwiftUI
import AppKit

// MARK: - 配色

enum Palette {
    static let high = Color(nsColor: .systemRed)
    static let medium = Color(nsColor: .systemOrange)
    static let low = Color(nsColor: .systemGray)

    static func priority(_ p: TaskPriority) -> Color {
        switch p {
        case .high: return high
        case .medium: return medium
        case .low: return low
        }
    }

    static let cardFill = Color(nsColor: .controlBackgroundColor).opacity(0.55)
    static let hairline = Color.primary.opacity(0.08)
    static let fieldFill = Color(nsColor: .textBackgroundColor).opacity(0.7)
}

// MARK: - 通用小控件

/// 圆形勾选按钮
struct CircleCheck: View {
    let isDone: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(isDone ? Color.accentColor : Color.primary.opacity(hovering ? 0.55 : 0.3), lineWidth: 1.4)
                    .frame(width: 18, height: 18)
                if isDone {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isDone ? "标记为未完成" : "标记为完成")
        .accessibilityLabel(isDone ? "标记为未完成" : "标记为完成")
    }
}

/// 紧凑图标按钮，带悬停反馈
struct IconButton: View {
    let systemName: String
    var help: String = ""
    var tint: Color = .secondary
    var size: CGFloat = 12
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(hovering ? tint : tint.opacity(0.8))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.09 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// 弹出面板里的小胶囊标签
struct TagPill: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

/// 毛玻璃背景（用于提醒浮窗）
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.layer?.cornerRadius = cornerRadius
    }
}

extension View {
    /// 统一的分组卡片外观
    func cardStyle(cornerRadius: CGFloat = 10) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
    }
}
