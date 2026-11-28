import AppKit
import CoreModel
import Importers
import SwiftUI

/// Ô soạn lời dạng văn bản dưới khung vẽ (mẫu `design/editor.html`, `.lyrics`). Chỉ hiện với bài hát. Dừng gõ
/// 400 ms thì lời được hợp nhất vào bộ trình chiếu (một bước hoàn tác); sửa ở nơi khác thì ô tự cập nhật.
struct LyricsPanel: View {
    let presentation: Presentation
    @Binding var isOpen: Bool
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen {
                Hairline()
                HStack(spacing: 0) {
                    LyricsTextView(
                        text: environment.editingLyricsText,
                        revision: environment.presentationEditing.lyricsRevision,
                        focusRequest: environment.presentationEditing.lyricsFocusRequest,
                        labelColors: labelColors,
                        onChange: { environment.lyricsDidChange($0) },
                        onEndEditing: { environment.flushLyrics() }
                    )
                    .frame(maxWidth: .infinity)
                    Hairline(vertical: true)
                    help.frame(width: 220, alignment: .topLeading)
                }
                .frame(height: 196)
            }
        }
        .background(Palette.bgPanel)
        .overlay(alignment: .top) { Hairline() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.text2)
                .accessibilityHidden(true)
            Text("Lyrics").font(Typography.controlStrong).foregroundStyle(Palette.text)
            Text("Edit here or on the canvas; both stay in sync")
                .font(Typography.caption)
                .foregroundStyle(Palette.text3)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                environment.splitSlidesByTheme()
            } label: {
                Label("Split slides by theme", systemImage: "rectangle.split.1x2")
            }
            .buttonStyle(ControlButtonStyle(small: true))
            .help(Text("Split long slides by the theme's line count"))
            IconButton(
                systemImage: isOpen ? "chevron.down" : "chevron.up",
                label: isOpen ? "Collapse lyrics" : "Expand lyrics", small: true
            ) {
                isOpen.toggle()
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 40)
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("[Verse 1], [Chorus], [Bridge], [Ending] start a new section.")
            Text("One blank line separates two slides.")
            Text("Stop typing for 0.4 s and the slides update; ⌘Z undoes the whole sync.")
        }
        .font(Typography.caption)
        .foregroundStyle(Palette.text3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Màu của từng nhãn "[Câu 1]" theo đoạn của bài.
    private var labelColors: [String: NSColor] {
        var colors: [String: NSColor] = [:]
        for group in presentation.groups {
            colors[LyricsText.labelName(group.label)] = NSColor(GroupColors.color(group))
        }
        return colors
    }
}

/// `NSTextView` chữ thường cho lời bài hát: nhãn "[...]" tô màu đoạn, không tự sửa chính tả, không hoàn tác riêng
/// (`⌘Z` của trình soạn hoàn tác cả lần hợp nhất).
private struct LyricsTextView: NSViewRepresentable {
    let text: String
    let revision: Int
    let focusRequest: Int
    let labelColors: [String: NSColor]
    let onChange: (String) -> Void
    let onEndEditing: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(Palette.bgStage)
        scroll.borderType = .noBorder
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.isRichText = false
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(Palette.bgStage)
        textView.insertionPointColor = NSColor(Palette.accent)
        textView.textContainerInset = NSSize(width: 16, height: 12)
        textView.font = LyricsStyle.bodyFont
        textView.textColor = NSColor(Palette.text)
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel(String(localized: "Lyrics as text"))
        context.coordinator.textView = textView
        context.coordinator.parent = self
        context.coordinator.load(text, colors: labelColors)
        context.coordinator.revision = revision
        context.coordinator.focusRequest = focusRequest
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        let isFocused = textView.window?.firstResponder === textView
        if coordinator.revision != revision || (!isFocused && textView.string != text) {
            coordinator.revision = revision
            if textView.string != text {
                coordinator.load(text, colors: labelColors)
            }
        }
        if coordinator.focusRequest != focusRequest {
            coordinator.focusRequest = focusRequest
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        var parent: LyricsTextView?
        var revision = 0
        var focusRequest = 0
        private var isLoading = false

        /// Thay toàn bộ chữ, giữ vị trí con trỏ (cắt cho vừa) và vị trí cuộn.
        func load(_ text: String, colors: [String: NSColor]) {
            guard let textView, let storage = textView.textStorage else { return }
            isLoading = true
            defer { isLoading = false }
            let selection = textView.selectedRange()
            let visible = textView.enclosingScrollView?.contentView.bounds.origin
            storage.setAttributedString(NSAttributedString(string: text, attributes: LyricsStyle.bodyAttributes))
            LyricsStyle.highlightLabels(in: storage, colors: colors)
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            if let visible {
                textView.enclosingScrollView?.contentView.scroll(to: visible)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isLoading, let textView, let storage = textView.textStorage else { return }
            LyricsStyle.highlightLabels(in: storage, colors: parent?.labelColors ?? [:])
            parent?.onChange(textView.string)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent?.onEndEditing()
        }
    }
}

/// Kiểu chữ của ô soạn lời.
@MainActor private enum LyricsStyle {
    static let bodyFont = NSFont.systemFont(ofSize: 13)
    static let labelFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = 1.3
        return [.font: bodyFont, .foregroundColor: NSColor(Palette.text), .paragraphStyle: paragraph]
    }

    /// Tô dòng nhãn "[...]" bằng màu đoạn (nhãn chưa có đoạn thì chữ phụ), các dòng khác về kiểu thân.
    static func highlightLabels(in storage: NSTextStorage, colors: [String: NSColor]) {
        let string = storage.string as NSString
        storage.beginEditing()
        storage.addAttributes(bodyAttributes, range: NSRange(location: 0, length: string.length))
        let whole = NSRange(location: 0, length: string.length)
        string.enumerateSubstrings(in: whole, options: .byLines) { line, range, _, _ in
            guard let line else { return }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 else { return }
            let name = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            let color = colors[name] ?? NSColor(Palette.text3)
            storage.addAttributes([.font: labelFont, .foregroundColor: color], range: range)
        }
        storage.endEditing()
    }
}
