import CoreModel
import SwiftUI
import UniformTypeIdentifiers

/// Chế độ Soạn thảo theo mẫu `design/editor.html`: trái là đoạn và trang, giữa là khung vẽ và ô soạn lời, phải là
/// thuộc tính. Kéo tệp vào cửa sổ để nhập.
struct EditorWorkspace: View {
    @Environment(AppEnvironment.self) private var environment
    @SceneStorage("editor.lyricsOpen") private var lyricsOpen = true
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var editing = environment.presentationEditing
        Group {
            if let presentation = environment.editingPresentation {
                HStack(spacing: 0) {
                    SectionList(presentation: presentation)
                        .frame(width: 248)
                        .background(Palette.bgPanel)
                    Hairline(vertical: true)
                    VStack(spacing: 0) {
                        DocumentHeader(presentation: presentation)
                        EditorStage(presentation: presentation)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if presentation.kind == .song {
                            LyricsPanel(presentation: presentation, isOpen: $lyricsOpen)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Hairline(vertical: true)
                    PresentationInspector(presentation: presentation)
                        .frame(width: Metrics.railRight)
                        .background(Palette.bgPanel)
                }
            } else {
                EditorStart()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.bgStage)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Metrics.radiusLarge)
                    .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard !files.isEmpty else { return false }
            Task { await environment.importIntoEditor(files) }
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .sheet(item: $editing.importReport) { report in
            ImportReportSheet(report: report)
        }
        .onAppear { environment.openEditor(environment.editingPresentationID) }
        .onChange(of: environment.editingPresentationID) { _, id in environment.openEditor(id) }
        .onDisappear { environment.flushLyrics() }
    }
}

/// Chưa mở bộ nào: tạo mới, nhập, hoặc chọn một bộ gần đây.
private struct EditorStart: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: 20) {
            EmptyStateView(
                systemImage: "square.and.pencil",
                title: "Nothing to edit yet",
                message: "Create a song, start a blank presentation, import files, or pick a recent one below."
            ) {
                HStack(spacing: 8) {
                    Button("New song") { environment.createSong() }
                        .buttonStyle(ControlButtonStyle(kind: .primary))
                    Button("Blank presentation") { environment.createBlankPresentation() }
                        .buttonStyle(ControlButtonStyle())
                    Button("Import…") { EditorImport.choose(environment) }
                        .buttonStyle(ControlButtonStyle())
                }
            }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recently edited")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.text3)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                    ForEach(recent) { presentation in
                        RecentRow(presentation: presentation)
                    }
                }
                .frame(width: 420)
            }
        }
        .padding(24)
    }

    private var recent: [Presentation] {
        let all = environment.library?.presentations.values.map { $0 } ?? []
        return Array(all.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(8))
    }
}

private struct RecentRow: View {
    let presentation: Presentation
    @Environment(AppEnvironment.self) private var environment
    @State private var isHovered = false

    var body: some View {
        Button {
            environment.openEditor(presentation.id)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: presentation.song?.number ?? "")
                    .font(Typography.numberSmall)
                    .foregroundStyle(Palette.text3)
                    .frame(width: 32, alignment: .leading)
                Text(verbatim: presentation.title)
                    .font(Typography.body)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(presentation.modifiedAt, style: .date)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(isHovered ? Palette.bgHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Hộp chọn tệp để nhập (`⌘I`).
@MainActor enum EditorImport {
    static func choose(_ environment: AppEnvironment) {
        let urls = FilePicker.files(
            message: String(localized: "Choose lyrics (text, OpenLyrics) or PDF files to import"),
            prompt: String(localized: "Import"), types: AppEnvironment.importableTypes)
        guard !urls.isEmpty else { return }
        Task { await environment.importIntoEditor(urls) }
    }
}

/// Bảng kết quả nhập theo tệp: thành công, cảnh báo, lỗi.
private struct ImportReportSheet: View {
    let report: EditorImportReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                verbatim: String(
                    format: String(localized: "Imported %lld of %lld files"), report.successCount, report.rows.count)
            )
            .font(Typography.blockTitle)
            .foregroundStyle(Palette.text)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(report.rows) { row in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: symbol(row.status))
                                .foregroundStyle(color(row.status))
                                .frame(width: 16)
                                .accessibilityLabel(Text(statusName(row.status)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: row.filename).font(Typography.bodyStrong).foregroundStyle(Palette.text)
                                if !row.message.isEmpty {
                                    Text(verbatim: row.message)
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.text2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Hairline() }
                    }
                }
            }
            .frame(maxHeight: 320)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(ControlButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(Palette.bgOverlay)
    }

    private func symbol(_ status: EditorImportReport.Status) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    private func color(_ status: EditorImportReport.Status) -> Color {
        switch status {
        case .success: return Palette.ok
        case .warning: return Palette.late
        case .failure: return Palette.danger
        }
    }

    private func statusName(_ status: EditorImportReport.Status) -> LocalizedStringKey {
        switch status {
        case .success: return "Imported"
        case .warning: return "Imported with warnings"
        case .failure: return "Not imported"
        }
    }
}
