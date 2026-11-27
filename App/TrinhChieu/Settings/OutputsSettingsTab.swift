import RenderEngine
import SwiftUI

/// Cài đặt > Đầu ra: sơ đồ màn theo vị trí thật, gán vai cho từng màn, hiện số trên từng màn.
struct OutputsSettingsTab: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let displays = environment.outputs.displays
        SettingsPage {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Connected screens") {
                    Text("Positions follow the macOS arrangement")
                }
                ScreenArrangement(displays: displays)
            }
            SettingsGroup {
                ForEach(Array(displays.enumerated()), id: \.element.uuid) { index, display in
                    ScreenRow(number: index + 1, display: display, isLast: index == displays.count - 1)
                }
                ForEach(missingAssignments, id: \.displayUUID) { assignment in
                    MissingScreenRow(assignment: assignment)
                }
            }
            HStack(spacing: 12) {
                Button {
                    environment.outputs.identifyScreens()
                } label: {
                    Label("Show number on each screen", systemImage: "number")
                }
                .buttonStyle(ControlButtonStyle())
                Text("Each screen shows a large number for 3 seconds so you know which is which.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
            }
            Label(
                "Choosing \"Main output\" for another screen moves the screen that had it to \"Not used\".",
                systemImage: "display"
            )
            .font(Typography.caption)
            .foregroundStyle(Palette.text3)
        }
    }

    private var missingAssignments: [OutputAssignment] {
        let present = Set(environment.outputs.displays.map(\.uuid))
        return environment.settings.value.outputAssignments.filter { !present.contains($0.displayUUID) }
    }
}

/// Lựa chọn vai trên giao diện: Đầu ra chính, Màn hình nhắc, Không dùng.
enum RoleChoice: Hashable {
    case role(OutputRole)
    case unused

    var role: OutputRole? {
        if case .role(let role) = self { return role }
        return nil
    }

    static let all: [SegmentedChoice<RoleChoice>.Option] = [
        .init(value: .role(.program), title: OutputRole.program.localizedName),
        .init(value: .role(.stage), title: OutputRole.stage.localizedName),
        .init(value: .unused, title: String(localized: "Not used")),
    ]
}

private struct ScreenRow: View {
    let number: Int
    let display: DisplayDescriptor
    let isLast: Bool
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let holdsMainWindow = display.uuid == environment.outputs.controlDisplayUUID
        let assigned = environment.settings.value.role(forDisplay: display.uuid)
        HStack(spacing: 14) {
            NumberBadge(number: number)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: display.name).font(Typography.body).foregroundStyle(Palette.text)
                Text(verbatim: details(holdsMainWindow: holdsMainWindow))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if holdsMainWindow && assigned == nil {
                Label("Cannot be assigned", systemImage: "lock")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text2)
                    .padding(.horizontal, 8)
                    .frame(height: Metrics.controlHeightSmall)
                    .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(Palette.bgRaised))
                    .help(Text("This screen holds the main window. Move the main window to another screen first."))
            } else {
                SegmentedChoice(
                    options: RoleChoice.all,
                    selection: Binding(
                        get: { assigned.map(RoleChoice.role) ?? .unused },
                        set: { environment.assign($0.role, to: display) }
                    ),
                    accessibilityTitle: Text(verbatim: display.name)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Hairline()
            }
        }
    }

    private func details(holdsMainWindow: Bool) -> String {
        var parts = ["\(display.pixelWidth) × \(display.pixelHeight)", "\(display.refreshRate) Hz"]
        if holdsMainWindow {
            parts.append(String(localized: "holds the system window"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Màn đã gán nhưng đang vắng: giữ vai để cắm lại tự gắn; bỏ gán được.
private struct MissingScreenRow: View {
    let assignment: OutputAssignment
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: 14) {
            NumberBadge(number: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: assignment.displayName).font(Typography.body).foregroundStyle(Palette.text2)
                Text(
                    verbatim: String(
                        format: String(localized: "%@ · disconnected, reattaches when plugged in"),
                        assignment.role.localizedName)
                )
                .font(Typography.caption)
                .foregroundStyle(Palette.late)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                environment.settings.value.assign(nil, toDisplay: assignment.displayUUID, name: assignment.displayName)
                environment.outputs.refresh()
            } label: {
                Text("Forget screen")
            }
            .buttonStyle(ControlButtonStyle(small: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Hairline() }
    }
}

private struct NumberBadge: View {
    let number: Int?

    var body: some View {
        Text(verbatim: number.map(String.init) ?? "–")
            .font(Typography.number)
            .foregroundStyle(Palette.text2)
            .frame(width: 24, height: 24)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineStrong, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// Sơ đồ các màn theo khung thật của macOS, thu nhỏ vừa ô; màn đầu ra chính viền cam đất.
private struct ScreenArrangement: View {
    let displays: [DisplayDescriptor]
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        GeometryReader { proxy in
            let layout = Self.layout(displays: displays, in: proxy.size)
            ZStack(alignment: .topLeading) {
                DotGrid()
                ForEach(Array(displays.enumerated()), id: \.element.uuid) { index, display in
                    if let rect = layout[display.uuid] {
                        tile(number: index + 1, display: display)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
        .frame(height: 220)
        .background(Palette.bgStage)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radiusLarge).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func tile(number: Int, display: DisplayDescriptor) -> some View {
        let role = environment.settings.value.role(forDisplay: display.uuid)
        let holdsMainWindow = display.uuid == environment.outputs.controlDisplayUUID
        let isProgram = role == .program
        return VStack(spacing: 2) {
            Text(verbatim: role.map { "\(number) · \($0.localizedName)" } ?? "\(number)")
                .font(Typography.controlStrong)
                .foregroundStyle(role == nil ? Palette.text2 : Palette.text)
            Text(verbatim: display.name).font(Typography.caption).foregroundStyle(Palette.text3)
            if holdsMainWindow {
                Text("Main window").font(Typography.caption).foregroundStyle(Palette.text3)
            }
        }
        .lineLimit(1)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.radius).fill(role == nil ? Palette.bgPanel : Palette.bgRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius)
                .strokeBorder(
                    isProgram ? Palette.accent : Palette.lineStrong,
                    style: StrokeStyle(
                        lineWidth: isProgram ? 2 : 1, dash: role == nil && !holdsMainWindow ? [3, 3] : [])
                )
        )
        .overlay(alignment: .topTrailing) {
            if let role {
                Lamp(style: environment.outputs.attached[role] != nil ? .breathing(Palette.accent) : .idle)
                    .padding(6)
            }
        }
    }

    /// Khung từng màn trong ô vẽ: giữ tỉ lệ thật, căn giữa, chừa lề 24.
    static func layout(displays: [DisplayDescriptor], in size: CGSize) -> [String: CGRect] {
        guard !displays.isEmpty, size.width > 48, size.height > 48 else { return [:] }
        let bounds = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let inset: CGFloat = 24
        let gap: CGFloat = 6
        let scale = min((size.width - inset * 2) / bounds.width, (size.height - inset * 2) / bounds.height)
        let drawn = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let origin = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        var result: [String: CGRect] = [:]
        for display in displays {
            // Toạ độ macOS có gốc dưới trái; ô vẽ có gốc trên trái.
            let x = origin.x + (display.frame.minX - bounds.minX) * scale
            let y = origin.y + (bounds.maxY - display.frame.maxY) * scale
            let rect = CGRect(x: x, y: y, width: display.frame.width * scale, height: display.frame.height * scale)
            result[display.uuid] = rect.insetBy(dx: gap / 2, dy: gap / 2)
        }
        return result
    }
}

/// Lưới chấm mờ làm nền sơ đồ.
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 16
            var y: CGFloat = step / 2
            while y < size.height {
                var x: CGFloat = step / 2
                while x < size.width {
                    let dot = Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                    context.fill(dot, with: .color(Palette.line))
                    x += step
                }
                y += step
            }
        }
        .accessibilityHidden(true)
    }
}
