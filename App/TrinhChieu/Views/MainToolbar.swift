import CoreModel
import SwiftUI

/// Thanh công cụ tự vẽ của cửa sổ chính (mẫu `design/live.html`): chế độ, ô mở Bảng lệnh, chỉ báo khung hình,
/// Tập dượt, Đóng băng, ẩn hiện cột phải.
struct MainToolbar: View {
    @Binding var mode: WorkspaceMode
    @Binding var showsRightRail: Bool
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: 8) {
            ModeSwitcher(mode: $mode)
            Spacer(minLength: 12)
            PaletteLauncher()
                .frame(minWidth: 220, maxWidth: 440)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                FrameMeter()
                RehearsalToggle()
                FreezeToggle()
                IconButton(
                    systemImage: "sidebar.right",
                    label: "Show or hide right column",
                    shortcutHint: "⌥⌘0",
                    isOn: showsRightRail && mode == .live
                ) {
                    showsRightRail.toggle()
                }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(mode != .live)
            }
            .fixedSize()
        }
        .padding(.leading, Metrics.trafficLightInset)
        .padding(.trailing, 12)
        .frame(height: Metrics.toolbarHeight)
        .background {
            ZStack {
                Palette.bgPanel
                WindowDragArea()
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Điều khiển phân đoạn Trực tiếp / Soạn thảo (`⌘1`, `⌘2`).
struct ModeSwitcher: View {
    @Binding var mode: WorkspaceMode

    var body: some View {
        HStack(spacing: 0) {
            segment(.live, title: "Live", key: "1")
            Rectangle().fill(Palette.lineStrong).frame(width: 1)
            segment(.editor, title: "Editor", key: "2")
        }
        .frame(height: Metrics.controlHeight)
        .background(Palette.bgRaised)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.lineStrong, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Mode"))
    }

    private func segment(_ value: WorkspaceMode, title: LocalizedStringKey, key: KeyEquivalent) -> some View {
        let selected = mode == value
        return Button {
            mode = value
        } label: {
            Text(title)
                .font(Typography.controlStrong)
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
        .keyboardShortcut(key, modifiers: .command)
        .help(Text(title) + Text(verbatim: " (⌘\(key.character))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Ô tìm trên thanh công cụ: mở Bảng lệnh (`⌘K`). Bảng lệnh làm ở T1.10; tới lúc đó ô chỉ hiển thị.
struct PaletteLauncher: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.text3)
                .accessibilityHidden(true)
            Text("Search songs, Bible verses, commands…")
                .font(Typography.body)
                .foregroundStyle(Palette.text3)
                .lineLimit(1)
            Spacer(minLength: 4)
            KeyCap(keys: "⌘K")
        }
        .padding(.horizontal, 10)
        .frame(height: Metrics.controlHeight)
        .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(Palette.bgRaised))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.lineStrong, lineWidth: 1))
        .opacity(0.75)
        .help(Text("Command palette arrives in a later update"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Open command palette"))
    }
}

/// Công tắc trạng thái trên thanh công cụ (`.state-btn`): khối rõ, có đèn và phím tắt.
private struct StateToggleLabel: View {
    let title: LocalizedStringKey
    let keys: String
    let isOn: Bool
    let tint: Color
    let soft: Color
    let breathes: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Lamp(style: isOn ? (breathes ? .breathing(tint) : .steady(tint)) : .off)
            Text(title).font(Typography.controlStrong)
            KeyCap(keys: keys, bare: true)
        }
        .foregroundStyle(isOn ? tint : Palette.text)
        .padding(.horizontal, 10)
        .frame(height: Metrics.controlHeight)
        .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(isOn ? soft : Palette.bgRaised))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.radius)
                .strokeBorder(isOn ? tint : (isHovered ? Palette.text3 : Palette.lineStrong), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

/// Tập dượt (`⌘R`): chạy thật nhưng đầu ra chính không đổi.
struct RehearsalToggle: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let isOn = environment.show?.state.isRehearsal ?? false
        Button {
            environment.send(.setRehearsal(!isOn))
        } label: {
            StateToggleLabel(
                title: isOn ? "Rehearsing" : "Rehearsal", keys: "⌘R", isOn: isOn, tint: Palette.warn,
                soft: Palette.warnSoft, breathes: true)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("r", modifiers: .command)
        .disabled(environment.show == nil)
        .help(Text("Run the show while the main output stays unchanged") + Text(verbatim: " (⌘R)"))
        .accessibilityLabel(Text("Rehearsal"))
        .accessibilityValue(Text(isOn ? LocalizedStringKey("On") : LocalizedStringKey("Off")))
    }
}

/// Đóng băng (`⌘⇧F`): giữ nguyên hình đang chiếu.
struct FreezeToggle: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let isOn = environment.show?.state.isFrozen ?? false
        Button {
            environment.send(.setFreeze(!isOn))
        } label: {
            StateToggleLabel(
                title: "Freeze", keys: "⌘⇧F", isOn: isOn, tint: Palette.freeze, soft: Palette.freezeSoft,
                breathes: false)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: [.command, .shift])
        .disabled(environment.show == nil)
        .help(Text("Hold the picture currently shown") + Text(verbatim: " (⌘⇧F)"))
        .accessibilityLabel(Text("Freeze"))
        .accessibilityValue(Text(isOn ? LocalizedStringKey("On") : LocalizedStringKey("Off")))
    }
}

/// Chỉ báo khung hình: chấm xanh, vàng, đỏ theo `RenderStatistics`; bấm để xem chi tiết từng đầu ra.
struct FrameMeter: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsDetails = false

    var body: some View {
        let health = environment.frameHealth
        Button {
            showsDetails.toggle()
        } label: {
            HStack(spacing: 8) {
                Lamp(style: lampStyle(health.level))
                Text(verbatim: headline(health))
                    .font(Typography.numberSmall)
                    .foregroundStyle(Palette.text2)
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.controlHeight)
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: summary(health)))
        .accessibilityLabel(Text("Frame rate"))
        .accessibilityValue(Text(verbatim: summary(health)))
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            FrameDetails(health: health)
        }
    }

    private func lampStyle(_ level: FrameHealth.Level) -> Lamp.Style {
        switch level {
        case .idle: return .idle
        case .smooth: return .breathing(Palette.ok)
        case .degraded: return .steady(Palette.late)
        case .poor: return .steady(Palette.danger)
        }
    }

    private func headline(_ health: FrameHealth) -> String {
        guard let fps = health.headlineFramesPerSecond else { return String(localized: "No output") }
        return String(format: String(localized: "%lld fps"), fps)
    }

    private func summary(_ health: FrameHealth) -> String {
        switch health.level {
        case .idle: return String(localized: "No output is attached")
        case .smooth: return String(localized: "Frames are steady, none dropped")
        case .degraded, .poor:
            return String(format: String(localized: "%lld frames dropped in the last minute"), health.droppedLastMinute)
        }
    }
}

private struct FrameDetails: View {
    let health: FrameHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frames per output").font(Typography.bodyStrong)
            if health.outputs.isEmpty {
                Text("No output is attached").font(Typography.control).foregroundStyle(Palette.text3)
            }
            ForEach(health.outputs) { output in
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: output.role.localizedName).font(Typography.controlStrong)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                        row("Frames per second", value: "\(output.framesPerSecond)")
                        row("Dropped in last minute", value: "\(output.droppedLastMinute)")
                        row("GPU time per frame", value: String(format: "%.1f ms", output.gpuMilliseconds))
                        row("Pipeline latency", value: String(format: "%.0f ms", output.latencyMilliseconds))
                        row("Scene change to screen", value: sceneLatency(output))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }

    /// "18 ms · 1,1 khung": thời gian từ lúc gửi cảnh mới (bấm thẻ) tới lúc lên màn.
    private func sceneLatency(_ output: FrameHealth.OutputSummary) -> String {
        guard let milliseconds = output.sceneLatencyMilliseconds, let frames = output.sceneLatencyFrames else {
            return "–"
        }
        return String(format: String(localized: "%.0f ms · %.1f frames"), milliseconds, frames)
    }

    private func row(_ title: LocalizedStringKey, value: String) -> some View {
        GridRow {
            Text(title).font(Typography.caption).foregroundStyle(Palette.text3)
            Text(verbatim: value).font(Typography.number).foregroundStyle(Palette.text)
        }
    }
}
