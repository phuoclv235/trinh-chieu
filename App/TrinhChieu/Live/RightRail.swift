import AppKit
import CoreModel
import RenderEngine
import SwiftUI

/// Cột phải của chế độ Trực tiếp (mẫu `design/live.html`, `.right`): xem trước hai đầu ra, luồng tín hiệu với các
/// nút xoá lớp, đồng hồ giờ thật.
struct LiveRightRail: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                OutputPreviewCard(role: .program)
                Hairline()
                OutputPreviewCard(role: .stage)
                Hairline()
                SignalFlowBlock()
                Hairline()
                LiveClockBlock()
            }
        }
        .scrollIndicators(.never)
    }
}

// MARK: - Luồng tín hiệu

/// Khối "Luồng tín hiệu": lớp là nút bên trái (bấm để xoá lớp), đầu ra là nút bên phải, dây cam đất chảy khi lớp
/// đang ra đầu ra. Phím F1 đến F4 làm cùng việc (``LiveKeyMonitor``).
struct SignalFlowBlock: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let layers = LayerSummary(environment: environment)
        let programOn = environment.outputs.attached[.program] != nil
        let stageOn = environment.outputs.attached[.stage] != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Signal flow").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text2)
                Spacer(minLength: 8)
                Text("Click a layer to clear").font(Typography.caption).foregroundStyle(Palette.text3)
            }
            HStack(spacing: 0) {
                VStack(spacing: 8) {
                    LayerNode(
                        title: "Text", detail: layers.text ?? String(localized: "Empty"), keys: "F2",
                        isOn: layers.text != nil, help: "Clear the text layer"
                    ) {
                        environment.send(.clearLayer(.slide))
                    }
                    LayerNode(
                        title: "Background", detail: layers.background ?? String(localized: "Empty"), keys: "F3",
                        isOn: layers.background != nil, help: "Clear the background layer"
                    ) {
                        environment.send(.clearLayer(.background))
                    }
                    LayerNode(
                        title: "Audio", detail: layers.audio ?? String(localized: "Not playing"), keys: "F4",
                        isOn: layers.audio != nil, help: "Mute the media that is playing"
                    ) {
                        environment.clearAudio()
                    }
                }
                .frame(width: 136)
                FlowWires(
                    wires: [
                        .init(fromRow: 0, toOutput: 0, isOn: layers.text != nil && programOn),
                        .init(fromRow: 1, toOutput: 0, isOn: layers.background != nil && programOn),
                        .init(fromRow: 0, toOutput: 1, isOn: layers.text != nil && stageOn),
                    ],
                    stubRow: 2
                )
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                VStack(spacing: 8) {
                    OutputNode(role: .program)
                    OutputNode(role: .stage)
                }
                .padding(.top, 10)
                .frame(width: 112, alignment: .top)
            }
            .frame(height: 148, alignment: .top)
            Button {
                environment.send(.clearAll)
            } label: {
                HStack(spacing: 8) {
                    Text("Clear all")
                    KeyCap(keys: "F1")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ControlButtonStyle())
            .disabled(!layers.hasAnything)
            .help(Text("Clear every layer from the main output") + Text(verbatim: " (F1)"))
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Nội dung đang có của từng lớp, viết thành một dòng ngắn cho nút lớp.
@MainActor private struct LayerSummary {
    var text: String?
    var background: String?
    var audio: String?
    var hasAnything: Bool

    init(environment: AppEnvironment) {
        let state = environment.show?.state
        hasAnything = !(state?.layers.isEmpty ?? true) || state?.live != nil
        if state?.layers[.slide] != nil, let live = state?.live,
            let sequence = environment.sequence(for: live.source),
            let index = sequence.index(of: live)
        {
            let firstLine = SlideCards.plainText(sequence.slides[index].slide)
                .split(separator: "\n", maxSplits: 1).first.map(String.init)
            text = firstLine ?? sequence.title
        }
        if case .background(let background, _)? = state?.layers[.background] {
            switch background.kind {
            case .none:
                break
            case .color:
                self.background = String(localized: "Solid color")
            case .media:
                let info = background.mediaID.flatMap { environment.library?.media[$0] }
                self.background = info?.originalName ?? String(localized: "Media")
            }
            if environment.backgroundHasSound, let id = background.mediaID {
                audio = environment.library?.media[id]?.originalName
            }
        }
    }
}

/// Nút lớp (`.node`): đèn, tên lớp, nội dung, phím tắt, cổng ra bên phải.
private struct LayerNode: View {
    let title: LocalizedStringKey
    let detail: String
    let keys: String
    let isOn: Bool
    let help: LocalizedStringKey
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Lamp(style: isOn ? .breathing(Palette.accent) : .idle)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOn ? Palette.text : Palette.text3)
                    Text(verbatim: detail).font(Typography.small).foregroundStyle(Palette.text3)
                        .lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 0)
                KeyCap(keys: keys, bare: true)
            }
            .padding(.leading, 9)
            .padding(.trailing, 10)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(isOn ? Palette.bgRaised : Palette.bgStage))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radius)
                    .strokeBorder(isHovered && isOn ? Palette.text3 : Palette.lineStrong, lineWidth: 1)
            )
            .overlay(alignment: .trailing) { Port(isOn: isOn).offset(x: 4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn)
        .onHover { isHovered = $0 }
        .help(Text(help) + Text(verbatim: " (\(keys))"))
        .accessibilityLabel(Text(help))
        .accessibilityValue(Text(verbatim: detail))
    }
}

/// Nút đầu ra (`.out-node`): tên vai, màn đang gán, đèn, cổng vào bên trái.
private struct OutputNode: View {
    let role: OutputRole
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let display = environment.outputs.attached[role]
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: role.localizedName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.trailing, 12)
            Text(verbatim: display?.name ?? String(localized: "No screen"))
                .font(Typography.small).foregroundStyle(Palette.text3).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 60, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(Palette.bgStage))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius)
                .strokeBorder(display != nil ? Palette.accent : Palette.lineStrong, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Lamp(style: display != nil ? .breathing(Palette.accent) : .off).padding(.top, 9).padding(.trailing, 8)
        }
        .overlay(alignment: .leading) { Port(isOn: display != nil).offset(x: -4) }
        .help(Text(verbatim: display.map { "\($0.name) · \($0.pixelWidth)×\($0.pixelHeight)" } ?? ""))
        .accessibilityElement(children: .combine)
    }
}

/// Cổng nối dây (`.port`): tròn 7 px viền 1,5 px.
private struct Port: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? Palette.accent : Palette.bgPanel)
            .overlay(Circle().strokeBorder(isOn ? Palette.accent : Palette.text3, lineWidth: 1.5))
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}

/// Dây nối lớp với đầu ra, vẽ bằng `CAShapeLayer`: dòng chảy chạy trong tiến trình vẽ của hệ điều hành, không bắt
/// SwiftUI vẽ lại mỗi khung.
private struct FlowWires: NSViewRepresentable {
    struct Wire: Equatable {
        let fromRow: Int
        let toOutput: Int
        let isOn: Bool
    }

    let wires: [Wire]
    /// Hàng của lớp chưa nối đầu ra nào (Âm thanh): vẽ một đoạn ngắn tắt.
    let stubRow: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> WireCanvas {
        WireCanvas()
    }

    func updateNSView(_ view: WireCanvas, context: Context) {
        view.configure(wires: wires, stubRow: stubRow, reduceMotion: reduceMotion)
    }
}

private final class WireCanvas: NSView {
    private var wires: [FlowWires.Wire] = []
    private var stubRow = 2
    private var reduceMotion = false
    private var shapes: [CAShapeLayer] = []
    private static let flowKey = "flow"

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không dùng")
    }

    override var isFlipped: Bool { true }

    func configure(wires: [FlowWires.Wire], stubRow: Int, reduceMotion: Bool) {
        guard wires != self.wires || stubRow != self.stubRow || reduceMotion != self.reduceMotion else { return }
        self.wires = wires
        self.stubRow = stubRow
        self.reduceMotion = reduceMotion
        needsLayout = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true
    }

    /// Tâm hàng của nút lớp (cao 44, cách 8) và của nút đầu ra (cao 60, cách 8, lùi xuống 10).
    private func layerY(_ row: Int) -> CGFloat { 22 + CGFloat(row) * 52 }
    private func outputY(_ index: Int) -> CGFloat { 40 + CGFloat(index) * 68 }

    override func layout() {
        super.layout()
        guard let root = layer else { return }
        for shape in shapes {
            shape.removeFromSuperlayer()
        }
        shapes = []
        let width = bounds.width
        var accent: CGColor = NSColor.orange.cgColor
        var idle: CGColor = NSColor.gray.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            accent = NSColor(Palette.accent).cgColor
            idle = NSColor(Palette.lineStrong).cgColor
        }
        // Dây tắt vẽ trước, dây sáng đè lên.
        for wire in wires.sorted(by: { !$0.isOn && $1.isOn }) {
            let path = CGMutablePath()
            let start = CGPoint(x: 0, y: layerY(wire.fromRow))
            let end = CGPoint(x: width, y: outputY(wire.toOutput))
            path.move(to: start)
            path.addCurve(
                to: end, control1: CGPoint(x: width * 0.56, y: start.y), control2: CGPoint(x: width * 0.44, y: end.y))
            shapes.append(makeShape(path, isOn: wire.isOn, accent: accent, idle: idle))
        }
        let stub = CGMutablePath()
        stub.move(to: CGPoint(x: 0, y: layerY(stubRow)))
        stub.addLine(to: CGPoint(x: width * 0.5, y: layerY(stubRow)))
        shapes.append(makeShape(stub, isOn: false, accent: accent, idle: idle))
        for shape in shapes {
            root.addSublayer(shape)
        }
    }

    private func makeShape(_ path: CGPath, isOn: Bool, accent: CGColor, idle: CGColor) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.frame = bounds
        shape.path = path
        shape.fillColor = nil
        shape.lineWidth = 1.5
        shape.strokeColor = isOn ? accent : idle
        shape.lineDashPattern = isOn ? [4, 2] : [2, 3]
        if isOn && !reduceMotion {
            let flow = CABasicAnimation(keyPath: "lineDashPhase")
            flow.fromValue = 0
            flow.toValue = -12
            flow.duration = 1.2
            flow.repeatCount = .infinity
            shape.add(flow, forKey: Self.flowKey)
        }
        return shape
    }
}

// MARK: - Đồng hồ

/// Khối "Giờ thật": ngày (gọi Chúa Nhật theo cách Hội Thánh), giờ lớn, giờ trang đang chiếu lên màn.
struct LiveClockBlock: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Real time").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text2)
                    Spacer(minLength: 8)
                    Text(verbatim: LiveClock.dayText(context.date)).font(Typography.caption)
                        .foregroundStyle(Palette.text3)
                }
                .padding(.bottom, 8)
                Text(verbatim: LiveClock.timeText(context.date))
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    .tracking(-1)
                    .foregroundStyle(Palette.text)
                    .padding(.bottom, 8)
                    .accessibilityLabel(Text("Real time"))
                if let item = environment.livePlanItemID, let plan = environment.activePlan,
                    let actual = environment.actualStart(of: item)
                {
                    planRows(item: item, plan: plan, actual: actual)
                } else if let wentLive = environment.show?.state.live?.wentLiveAt {
                    ClockRow(
                        title: String(localized: "Current slide went live"), value: LiveClock.shortTime(wentLive))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Mục chương trình đang chiếu: giờ bắt đầu thật, chênh lệch với dự kiến, giờ kết thúc dự kiến.
    @ViewBuilder private func planRows(item: UUID, plan: ServicePlan, actual: Date) -> some View {
        let schedule = PlanSchedule(plan: plan)
        ClockRow(title: String(localized: "This item started"), value: LiveClock.shortTime(actual))
        if let planned = schedule.starts[item] {
            ClockRow(
                title: String(format: String(localized: "Compared with plan %@"), LiveClock.shortTime(planned)),
                value: Self.punctualityText(Punctuality(actual: actual, planned: planned)),
                tint: Punctuality.isLate(actual: actual, planned: planned) ? Palette.late : Palette.ok)
        }
        if let end = schedule.end {
            ClockRow(title: String(localized: "Planned end"), value: LiveClock.shortTime(end))
        }
    }

    static func punctualityText(_ punctuality: Punctuality) -> String {
        switch punctuality {
        case .onTime: return String(localized: "On time")
        case .early(let minutes): return String(format: String(localized: "%lld min early"), minutes)
        case .late(let minutes): return String(format: String(localized: "%lld min late"), minutes)
        }
    }
}

/// Một dòng của khối đồng hồ (`.clock__row`).
struct ClockRow: View {
    let title: String
    let value: String
    var tint: Color = Palette.text

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack {
                Text(verbatim: title).font(Typography.caption).foregroundStyle(Palette.text2)
                Spacer(minLength: 8)
                Text(verbatim: value).font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(tint)
            }
            .padding(.vertical, 4)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Định dạng giờ cho khối đồng hồ.
enum LiveClock {
    /// Tên thứ theo cách gọi của Hội Thánh Tin Lành: Chúa Nhật, không "Chủ Nhật".
    static let weekdays = ["Chúa Nhật", "Thứ Hai", "Thứ Ba", "Thứ Tư", "Thứ Năm", "Thứ Sáu", "Thứ Bảy"]

    /// "Chúa Nhật 30/11/2026".
    static func dayText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.weekday, .day, .month, .year], from: date)
        let weekday = weekdays[((parts.weekday ?? 1) - 1 + 7) % 7]
        return String(format: "%@ %02d/%02d/%d", weekday, parts.day ?? 1, parts.month ?? 1, parts.year ?? 2000)
    }

    /// "9:12:48".
    static func timeText(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// "9:10".
    static func shortTime(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}
