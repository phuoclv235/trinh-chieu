import SwiftUI

/// Nút khối của `design/ui.css` (`.btn`): viền 1 px `--line-strong`, bo 6 px, nền `--bg-raised`.
struct ControlButtonStyle: ButtonStyle {
    enum Kind {
        case standard
        /// Nút chính duy nhất của một màn (cam đất).
        case primary
        case danger
        /// Không viền, chữ phụ.
        case quiet
    }

    var kind: Kind = .standard
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        ControlButtonBody(configuration: configuration, kind: kind, small: small)
    }
}

private struct ControlButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ControlButtonStyle.Kind
    let small: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(small ? Typography.control : Typography.bodyStrong)
            .lineLimit(1)
            .padding(.horizontal, small ? 8 : 12)
            .frame(height: small ? Metrics.controlHeightSmall : Metrics.controlHeight)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(background))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radius))
            .brightness(isHovered && (kind == .primary || kind == .danger) ? 0.04 : 0)
            .onHover { isHovered = $0 }
    }

    private var foreground: Color {
        guard isEnabled else { return Palette.textDisabled }
        switch kind {
        case .standard: return Palette.text
        case .primary: return Palette.onAccent
        case .danger: return Palette.onDanger
        case .quiet: return isHovered ? Palette.text : Palette.text2
        }
    }

    private var background: Color {
        guard isEnabled else { return .clear }
        switch kind {
        case .standard:
            return configuration.isPressed ? Palette.bgPressed : (isHovered ? Palette.bgHover : Palette.bgRaised)
        case .primary: return Palette.accent
        case .danger: return Palette.dangerFill
        case .quiet: return .clear
        }
    }

    private var border: Color {
        guard isEnabled else { return Palette.line }
        switch kind {
        case .standard: return isHovered ? Palette.text3 : Palette.lineStrong
        case .primary: return Palette.accent
        case .danger: return Palette.dangerFill
        case .quiet: return .clear
        }
    }
}

/// Nút biểu tượng vuông 30 px (`.ibtn`). Luôn có chú giải kèm phím tắt và nhãn trợ năng.
struct IconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var shortcutHint: String?
    var isOn = false
    var small = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: small ? 11 : 13, weight: .medium))
                .frame(
                    width: small ? Metrics.controlHeightSmall : Metrics.controlHeight,
                    height: small ? Metrics.controlHeightSmall : Metrics.controlHeight
                )
                .foregroundStyle(isOn ? Palette.accent : (isHovered ? Palette.text : Palette.text2))
                .background(
                    RoundedRectangle(cornerRadius: Metrics.radius)
                        .fill(isOn ? Palette.accentSoft : (isHovered ? Palette.bgHover : Palette.bgRaised))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.radius)
                        .strokeBorder(
                            isOn ? Palette.accentLine : (isHovered ? Palette.text3 : Palette.lineStrong), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(Text(label))
    }

    private var helpText: Text {
        guard let shortcutHint else { return Text(label) }
        return Text(label) + Text(verbatim: " (\(shortcutHint))")
    }
}

/// Phím tắt hiển thị (`.kbd`): chữ số đều cột, viền mảnh.
struct KeyCap: View {
    let keys: String
    var bare = false

    var body: some View {
        Text(verbatim: keys)
            .font(Typography.numberSmall)
            .foregroundStyle(Palette.text3)
            .padding(.horizontal, bare ? 0 : 5)
            .frame(minWidth: bare ? 0 : 18, minHeight: 18)
            .overlay {
                if !bare {
                    RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineStrong, lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Tiêu đề khối trong cột: tên bên trái (15, đậm vừa), ghi chú phụ bên phải.
struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(Typography.bodyStrong).foregroundStyle(Palette.text)
            Spacer(minLength: 8)
            trailing.font(Typography.caption).foregroundStyle(Palette.text3).lineLimit(1)
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: LocalizedStringKey) {
        self.title = title
        trailing = EmptyView()
    }
}

/// Trạng thái rỗng có hướng đi tiếp.
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.text3)
                .accessibilityHidden(true)
            Text(title).font(Typography.blockTitle).foregroundStyle(Palette.text)
            Text(message)
                .font(Typography.control)
                .foregroundStyle(Palette.text3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            actions.padding(.top, 4)
        }
        .padding(24)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        actions = EmptyView()
    }
}

/// Đường chia vùng 1 px `--line`.
struct Hairline: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

/// Điều khiển phân đoạn (`.seg`): mục đang chọn nền `--bg-pressed` và vạch cam đất 2 px ở đáy.
struct SegmentedChoice<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
    }

    let options: [Option]
    @Binding var selection: Value
    var accessibilityTitle: Text

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 {
                    Rectangle().fill(Palette.lineStrong).frame(width: 1)
                }
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(verbatim: option.title)
                        .font(selected ? Typography.controlStrong : Typography.control)
                        .foregroundStyle(selected ? Palette.text : Palette.text2)
                        .padding(.horizontal, 12)
                        .frame(maxHeight: .infinity)
                        .background(selected ? Palette.bgPressed : Color.clear)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Rectangle().fill(Palette.accent).frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(height: Metrics.controlHeight)
        .background(Palette.bgRaised)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.lineStrong, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }
}

/// Nhãn trạng thái nhỏ (`.pill`): cao 20, bo 4, chữ 11 đậm vừa.
struct Pill: View {
    let text: String
    let foreground: Color
    let background: Color

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 4).fill(background))
    }
}
