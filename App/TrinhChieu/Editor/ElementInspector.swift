import AppKit
import CoreModel
import SwiftUI

// Các thẻ Chữ, Bố cục, Nền trang của bảng thuộc tính (mẫu `design/editor.html`, `.insp`). Mỗi lần sửa là một bước
// hoàn tác; sửa liền nhau trên cùng một trường (kéo thanh trượt, gõ số) gộp thành một bước.

// MARK: - Thẻ Chữ

/// Kiểu chữ của phần tử chữ đang chọn. Trường đang khác mẫu có chấm cam đất; "Về theo mẫu" bỏ mọi phần đè.
struct TextInspector: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if case .text(let text)? = environment.editingElement, let theme = environment.editingTheme {
            TextFields(text: text, theme: theme)
        } else {
            InspectorHint(message: "Choose a text box on the canvas to change its style.")
        }
    }
}

private struct TextFields: View {
    let text: TextElement
    let theme: Theme
    @Environment(AppEnvironment.self) private var environment

    private var base: TextStyle { text.baseSlot(in: theme).style }
    private var style: TextStyle { text.resolvedStyle(in: theme) }
    private var override: TextStyleOverride { text.style ?? TextStyleOverride() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorField("Font", reset: reset(\.fontFamily)) {
                Picker("Font", selection: value(\.fontFamily, \.fontFamily, key: "fontFamily")) {
                    Text("System").tag("system")
                    ForEach(FontFamilies.all, id: \.self) { family in
                        Text(verbatim: family).tag(family)
                    }
                }
                .labelsHidden()
            }
            HStack(alignment: .top, spacing: 8) {
                InspectorField("Weight", reset: reset(\.fontWeight)) {
                    Picker("Weight", selection: value(\.fontWeight, \.fontWeight, key: "fontWeight")) {
                        ForEach(FontWeights.all, id: \.value) { weight in
                            Text(weight.title).tag(weight.value)
                        }
                    }
                    .labelsHidden()
                }
                InspectorField("Font size", reset: reset(\.fontSize)) {
                    NumberField(
                        title: "Font size", unit: "pt",
                        value: value(\.fontSize, \.fontSize, key: "fontSize"), range: 8...400)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                InspectorField("Horizontal alignment", reset: reset(\.alignment)) {
                    IconChoice<CoreModel.TextAlignment>(
                        options: [
                            .init(value: .left, systemImage: "text.alignleft", label: "Align left"),
                            .init(value: .center, systemImage: "text.aligncenter", label: "Align center"),
                            .init(value: .right, systemImage: "text.alignright", label: "Align right"),
                        ],
                        selection: value(\.alignment, \.alignment, key: "alignment"),
                        accessibilityTitle: Text("Horizontal alignment"))
                }
                InspectorField("Vertical alignment", reset: reset(\.verticalAlignment)) {
                    IconChoice<CoreModel.VerticalAlignment>(
                        options: [
                            .init(value: .top, systemImage: "align.vertical.top", label: "Align top"),
                            .init(value: .middle, systemImage: "align.vertical.center", label: "Align middle"),
                            .init(value: .bottom, systemImage: "align.vertical.bottom", label: "Align bottom"),
                        ],
                        selection: value(\.verticalAlignment, \.verticalAlignment, key: "verticalAlignment"),
                        accessibilityTitle: Text("Vertical alignment"))
                }
            }
            InspectorField("Text color", reset: reset(\.color)) {
                ColorField(title: "Text color", color: value(\.color, \.color, key: "color"))
            }
            InspectorSlider(
                title: "Line spacing", reset: reset(\.lineHeight),
                value: value(\.lineHeight, \.lineHeight, key: "lineHeight"), range: 0.8...2.4, step: 0.05,
                format: { $0.formatted(.number.precision(.fractionLength(2)).locale(Self.locale)) })
            InspectorSlider(
                title: "Letter spacing", reset: reset(\.letterSpacing),
                value: value(\.letterSpacing, \.letterSpacing, key: "letterSpacing"), range: -10...40, step: 1,
                format: { $0.formatted(.number.precision(.fractionLength(0)).locale(Self.locale)) })
            InspectorGroup {
                InspectorSwitch(title: "Uppercase", reset: reset(\.transform), isOn: uppercase)
                InspectorSwitch(
                    title: "Text outline", reset: reset(\.stroke),
                    isOn: toggle(
                        \.stroke, \.stroke, key: "stroke", off: .none, on: TextStroke(color: .black, width: 4)))
                InspectorSwitch(
                    title: "Text shadow", reset: reset(\.shadow),
                    isOn: toggle(
                        \.shadow, \.shadow, key: "shadow", off: .none,
                        on: TextShadow(
                            color: RGBA(red: 0, green: 0, blue: 0, alpha: 170), radius: 8,
                            offset: PixelPoint(x: 0, y: 3))))
                InspectorSwitch(
                    title: "Box behind text", reset: reset(\.box),
                    isOn: toggle(
                        \.box, \.box, key: "box", off: .none,
                        on: TextBox(
                            color: RGBA(red: 0, green: 0, blue: 0, alpha: 150),
                            padding: CoreModel.EdgeInsets(top: 12, right: 24, bottom: 12, left: 24), cornerRadius: 8)))
                InspectorSwitch(
                    title: "Shrink text to fit", reset: reset(\.autoFit),
                    isOn: toggle(
                        \.autoFit, \.autoFit, key: "autoFit", off: .none, on: AutoFit(mode: .shrink, minScale: 0.5)))
            }
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        InspectorGroup {
            if text.slot != nil {
                Text("The frame follows the theme slot. Detach it to move or resize it freely.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Detach from theme") { environment.detachElement(text.id) }
                    .buttonStyle(ControlButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            let count = override.overriddenCount
            if count > 0 {
                Text(
                    verbatim: String(
                        format: String(localized: "%1$lld properties differ from theme %2$@"), count,
                        theme.name)
                )
                .font(Typography.caption)
                .foregroundStyle(Palette.text2)
                Button {
                    environment.editTextElement(String(localized: "Reset to theme")) { $0.style = nil }
                } label: {
                    Label("Reset to theme", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ControlButtonStyle())
            } else {
                Text(verbatim: String(format: String(localized: "Follows theme %@"), theme.name))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
            }
        }
    }

    private static let locale = Locale(identifier: "vi_VN")

    // MARK: Ràng buộc

    /// Một trường kiểu chữ: đọc kiểu đang thấy, ghi phần đè (trùng mẫu thì bỏ phần đè).
    private func value<Value: Equatable>(
        _ path: WritableKeyPath<TextStyleOverride, Value?>, _ basePath: WritableKeyPath<TextStyle, Value>,
        key: String
    ) -> Binding<Value> {
        let base = base
        return Binding(
            get: { style[keyPath: basePath] },
            set: { newValue in
                let name = String(localized: "Change text style")
                environment.editTextElement(name, coalescingKey: "style.\(key)") { element in
                    var override = element.style ?? TextStyleOverride()
                    override.set(path, newValue, base: base, basePath: basePath)
                    element.style = override.isEmpty ? nil : override
                }
            })
    }

    /// Bỏ phần đè của một trường; `nil` khi trường đang theo mẫu.
    private func reset<Value>(_ path: WritableKeyPath<TextStyleOverride, Value?>) -> (() -> Void)? {
        guard override[keyPath: path] != nil else { return nil }
        return {
            environment.editTextElement(String(localized: "Reset to theme")) { element in
                var override = element.style ?? TextStyleOverride()
                override[keyPath: path] = nil
                element.style = override.isEmpty ? nil : override
            }
        }
    }

    /// Công tắc bật tắt một hiệu ứng: bật thì dùng giá trị của mẫu nếu mẫu đã bật, không thì giá trị mặc định.
    private func toggle<Value: Equatable>(
        _ path: WritableKeyPath<TextStyleOverride, Value?>, _ basePath: WritableKeyPath<TextStyle, Value>,
        key: String, off: Value, on: Value
    ) -> Binding<Bool> {
        let field = value(path, basePath, key: key)
        let baseValue = base[keyPath: basePath]
        return Binding(
            get: { field.wrappedValue != off },
            set: { isOn in field.wrappedValue = isOn ? (baseValue != off ? baseValue : on) : off })
    }

    private var uppercase: Binding<Bool> {
        let field = value(\.transform, \.transform, key: "transform")
        return Binding(get: { field.wrappedValue == .uppercase }, set: { field.wrappedValue = $0 ? .uppercase : .none })
    }
}

/// Phông có trên máy, lấy một lần.
@MainActor private enum FontFamilies {
    static let all: [String] = NSFontManager.shared.availableFontFamilies.sorted {
        $0.localizedStandardCompare($1) == .orderedAscending
    }
}

@MainActor private enum FontWeights {
    struct Weight {
        let value: Int
        let title: LocalizedStringKey
    }

    static let all: [Weight] = [
        Weight(value: 300, title: "Light"), Weight(value: 400, title: "Regular"),
        Weight(value: 500, title: "Medium"), Weight(value: 600, title: "Semibold"),
        Weight(value: 700, title: "Bold"), Weight(value: 800, title: "Heavy"),
    ]
}

// MARK: - Thẻ Bố cục

/// Vị trí, cỡ (số nguyên điểm ảnh của khung vẽ), lớp, độ mờ và cách đặt media của phần tử đang chọn.
struct LayoutInspector: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let element = environment.editingElement, let theme = environment.editingTheme {
            LayoutFields(element: element, theme: theme)
        } else {
            InspectorHint(message: "Choose an element on the canvas to change its position and size.")
        }
    }
}

private struct LayoutFields: View {
    let element: Element
    let theme: Theme
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let locked = element.isLockedToTheme
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                InspectorField("X") { frameField("X", \.x, key: "x") }
                InspectorField("Y") { frameField("Y", \.y, key: "y") }
            }
            HStack(alignment: .top, spacing: 8) {
                InspectorField("Width") { frameField("Width", \.width, key: "width", minimum: 8) }
                InspectorField("Height") { frameField("Height", \.height, key: "height", minimum: 8) }
            }
            if locked {
                HStack(spacing: 8) {
                    Text("Follows the theme slot")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.text3)
                    Spacer(minLength: 8)
                    Button("Detach from theme") { environment.detachElement(element.id) }
                        .buttonStyle(ControlButtonStyle(small: true))
                }
            }
            media
            InspectorField("Layer") {
                HStack(spacing: 8) {
                    Button {
                        environment.bringElementForward(element.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Bring forward")
                            KeyCap(keys: "⌘]", bare: true)
                        }
                    }
                    Button {
                        environment.sendElementBackward(element.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Send backward")
                            KeyCap(keys: "⌘[", bare: true)
                        }
                    }
                }
                .buttonStyle(ControlButtonStyle(small: true))
            }
            InspectorGroup {
                Button(role: .destructive) {
                    environment.deleteElement(element.id)
                } label: {
                    HStack(spacing: 6) {
                        Text("Delete element")
                        KeyCap(keys: "⌫", bare: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ControlButtonStyle())
            }
        }
    }

    /// Phần riêng theo loại phần tử: độ mờ và cách đặt ảnh, lặp và tắt tiếng video, màu và bo góc hình.
    @ViewBuilder private var media: some View {
        switch element {
        case .image(let image):
            InspectorField("Fit") {
                fitPicker(Binding(get: { image.fit }, set: { fit in editImage("fit") { $0.fit = fit } }))
            }
            InspectorSlider(
                title: "Opacity", reset: nil,
                value: Binding(
                    get: { image.opacity },
                    set: { opacity in editImage("opacity") { $0.opacity = opacity } }),
                range: 0...1, step: 0.05, format: { "\(Int(($0 * 100).rounded())) %" })
        case .video(let video):
            InspectorField("Fit") {
                fitPicker(Binding(get: { video.fit }, set: { fit in editVideo("fit") { $0.fit = fit } }))
            }
            InspectorGroup {
                InspectorSwitch(
                    title: "Loop", reset: nil,
                    isOn: Binding(
                        get: { video.loop },
                        set: { loop in editVideo("loop") { $0.loop = loop } }))
                InspectorSwitch(
                    title: "Muted", reset: nil,
                    isOn: Binding(
                        get: { video.muted },
                        set: { muted in editVideo("muted") { $0.muted = muted } }))
            }
        case .shape(let shape):
            InspectorField("Fill") {
                ColorField(
                    title: "Fill",
                    color: Binding(
                        get: { shape.fill },
                        set: { fill in editShape("fill") { $0.fill = fill } }))
            }
            InspectorField("Corner radius") {
                NumberField(
                    title: "Corner radius", unit: "px",
                    value: Binding(
                        get: { shape.cornerRadius },
                        set: { radius in editShape("corner") { $0.cornerRadius = radius } }),
                    range: 0...2000)
            }
        case .text:
            EmptyView()
        }
    }

    private func fitPicker(_ fit: Binding<ContentFit>) -> some View {
        Picker("Fit", selection: fit) {
            Text("Fit inside").tag(ContentFit.fit)
            Text("Fill frame").tag(ContentFit.fill)
            Text("Stretch").tag(ContentFit.stretch)
        }
        .labelsHidden()
    }

    private func edit(_ key: String, _ change: @escaping (inout Element) -> Void) {
        environment.editElement(String(localized: "Change element"), coalescingKey: "element.\(key)", change)
    }

    private func editImage(_ key: String, _ change: @escaping (inout ImageElement) -> Void) {
        edit(key) { element in
            guard case .image(var value) = element else { return }
            change(&value)
            element = .image(value)
        }
    }

    private func editVideo(_ key: String, _ change: @escaping (inout VideoElement) -> Void) {
        edit(key) { element in
            guard case .video(var value) = element else { return }
            change(&value)
            element = .video(value)
        }
    }

    private func editShape(_ key: String, _ change: @escaping (inout ShapeElement) -> Void) {
        edit(key) { element in
            guard case .shape(var value) = element else { return }
            change(&value)
            element = .shape(value)
        }
    }

    private func frameField(
        _ title: LocalizedStringKey, _ path: WritableKeyPath<PixelRect, Double>, key: String, minimum: Double = -100_000
    ) -> some View {
        let frame = element.frame
        let id = element.id
        let field = NumberField(
            title: title, unit: nil,
            value: Binding(
                get: { (environment.editingSlide?.displayFrame(of: id, theme: theme) ?? frame)[keyPath: path] },
                set: { value in
                    var rect = frame
                    rect[keyPath: path] = value.rounded()
                    environment.setElementFrame(id, rect, coalescingKey: "frame.\(key).\(id.uuidString)")
                }),
            range: minimum...100_000)
        return field.disabled(element.isLockedToTheme)
    }
}

// MARK: - Thẻ Nền trang

/// Nền riêng của trang đang chọn: theo mẫu, một màu, hoặc ảnh, video trong thư viện Media.
struct BackgroundInspector: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if let slide = environment.editingSlide {
            BackgroundFields(background: slide.background)
        } else {
            InspectorHint(message: "Choose a slide on the left")
        }
    }
}

private struct BackgroundFields: View {
    let background: SlideBackground
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            InspectorField("Background") {
                SegmentedChoice(
                    options: [
                        .init(value: BackgroundKind.none, title: String(localized: "Theme")),
                        .init(value: BackgroundKind.color, title: String(localized: "Color")),
                        .init(value: BackgroundKind.media, title: String(localized: "Media")),
                    ],
                    selection: kind, accessibilityTitle: Text("Background"))
            }
            switch background.kind {
            case .none:
                Text("This slide uses the theme background.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.text3)
            case .color:
                InspectorField("Color") {
                    ColorField(
                        title: "Color",
                        color: Binding(
                            get: { background.color ?? .black },
                            set: { color in edit("color") { $0.color = color } }))
                }
            case .media:
                mediaFields
            }
        }
    }

    @ViewBuilder private var mediaFields: some View {
        let items = environment.libraryMedia(.image) + environment.libraryMedia(.video)
        let current = background.mediaID.flatMap { environment.library?.media[$0] }
        InspectorField("Media") {
            Menu {
                if items.isEmpty {
                    Text("The Media library is empty")
                }
                ForEach(items, id: \.id) { info in
                    Button {
                        edit("media") { $0.mediaID = info.id }
                    } label: {
                        Label(info.originalName, systemImage: info.kind == .video ? "film" : "photo")
                    }
                }
            } label: {
                Text(verbatim: current?.originalName ?? String(localized: "Choose media"))
                    .lineLimit(1)
            }
            .menuStyle(.button)
        }
        if current?.kind == .video {
            InspectorGroup {
                InspectorSwitch(
                    title: "Loop", reset: nil,
                    isOn: Binding(get: { background.loop ?? true }, set: { loop in edit("loop") { $0.loop = loop } }))
                InspectorSwitch(
                    title: "Muted", reset: nil,
                    isOn: Binding(
                        get: { background.muted ?? false }, set: { muted in edit("muted") { $0.muted = muted } }))
            }
        }
    }

    private var kind: Binding<BackgroundKind> {
        Binding(
            get: { background.kind },
            set: { kind in
                environment.editSlide(String(localized: "Change slide background")) { slide in
                    switch kind {
                    case .none: slide.background = .none
                    case .color: slide.background = .color(slide.background.color ?? .black)
                    case .media:
                        var media = slide.background
                        media.kind = .media
                        if media.loop == nil { media.loop = true }
                        if media.muted == nil { media.muted = false }
                        slide.background = media
                    }
                }
            })
    }

    private func edit(_ key: String, _ change: @escaping (inout SlideBackground) -> Void) {
        environment.editSlide(String(localized: "Change slide background"), coalescingKey: "background.\(key)") {
            change(&$0.background)
        }
    }
}

// MARK: - Thành phần chung

/// Lời nhắc khi thẻ chưa có gì để sửa.
private struct InspectorHint: View {
    let message: LocalizedStringKey

    var body: some View {
        Text(message)
            .font(Typography.body)
            .foregroundStyle(Palette.text3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

/// Nhãn trường (`.field__label`), có chấm cam đất khi đang khác mẫu.
private struct InspectorField<Content: View>: View {
    let title: LocalizedStringKey
    /// Có khi trường đang khác mẫu: chấm cam đất, nhấn để về theo mẫu.
    var reset: (() -> Void)?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, reset: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.reset = reset
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let reset { OverrideDot(reset: reset) }
                Text(title)
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.text2)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Chấm "đang khác mẫu" (`.override-dot`): nhấn để trường đó về theo mẫu.
private struct OverrideDot: View {
    let reset: () -> Void

    var body: some View {
        Button(action: reset) {
            Circle()
                .fill(Palette.accent)
                .frame(width: 6, height: 6)
                .padding(3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Differs from theme. Click to reset to theme"))
        .accessibilityLabel(Text("Reset to theme"))
    }
}

/// Nhóm có vạch kẻ trên (`.insp__group`).
private struct InspectorGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Hairline() }
    }
}

/// Dòng công tắc (`.insp__line`).
private struct InspectorSwitch: View {
    let title: LocalizedStringKey
    let reset: (() -> Void)?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 5) {
                if let reset { OverrideDot(reset: reset) }
                Text(title).font(Typography.body).foregroundStyle(Palette.text)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(Palette.accent)
    }
}

/// Thanh trượt có giá trị số bên phải nhãn.
private struct InspectorSlider: View {
    let title: LocalizedStringKey
    let reset: (() -> Void)?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let reset { OverrideDot(reset: reset) }
                Text(title)
                Spacer(minLength: 8)
                Text(verbatim: format(value)).font(Typography.number).foregroundStyle(Palette.text3)
            }
            .font(Typography.caption)
            .foregroundStyle(Palette.text2)
            Slider(value: $value, in: range, step: step)
                .controlSize(.small)
                .tint(Palette.accent)
                .accessibilityLabel(Text(title))
        }
    }
}

/// Ô số: gõ rồi nhấn Return hoặc rời ô thì lưu; giá trị kẹp trong `range`.
private struct NumberField: View {
    let title: LocalizedStringKey
    let unit: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(title, text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(Typography.number)
                .multilineTextAlignment(.trailing)
                .labelsHidden()
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
            if let unit {
                Text(verbatim: unit).font(Typography.caption).foregroundStyle(Palette.text3)
            }
        }
        .onAppear { draft = Self.text(value) }
        .onChange(of: value) { _, newValue in
            if !isFocused { draft = Self.text(newValue) }
        }
    }

    private func commit() {
        let normalized = draft.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let number = Double(normalized) else {
            draft = Self.text(value)
            return
        }
        let clamped = min(max(number, range.lowerBound), range.upperBound)
        if clamped != value { value = clamped }
        draft = Self.text(clamped)
    }

    private static func text(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Phân đoạn biểu tượng (`.seg--icon`).
private struct IconChoice<Value: Hashable>: View {
    struct Option {
        let value: Value
        let systemImage: String
        let label: LocalizedStringKey
    }

    let options: [Option]
    @Binding var selection: Value
    let accessibilityTitle: Text

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 { Rectangle().fill(Palette.lineStrong).frame(width: 1) }
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Image(systemName: option.systemImage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Palette.text : Palette.text2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(selected ? Palette.bgPressed : Color.clear)
                        .overlay(alignment: .bottom) {
                            if selected { Rectangle().fill(Palette.accent).frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(option.label))
                .accessibilityLabel(Text(option.label))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .frame(height: Metrics.controlHeight)
        .background(Palette.bgRaised)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.lineStrong, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
    }
}

/// Ô màu: ô chọn màu của hệ thống cạnh mã `#RRGGBB`.
private struct ColorField: View {
    let title: LocalizedStringKey
    @Binding var color: RGBA
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            ColorPicker(title, selection: swiftUIColor, supportsOpacity: true)
                .labelsHidden()
            TextField(title, text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(Typography.number)
                .labelsHidden()
                .focused($isFocused)
                .onSubmit { commit() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commit() }
                }
        }
        .onAppear { draft = Self.text(color) }
        .onChange(of: color) { _, newValue in
            if !isFocused { draft = Self.text(newValue) }
        }
    }

    private var swiftUIColor: Binding<Color> {
        Binding(
            get: { color.swiftUIColor },
            set: { if let rgba = RGBA($0), rgba != color { color = rgba } })
    }

    private func commit() {
        var hex = draft.trimmingCharacters(in: .whitespaces)
        if !hex.hasPrefix("#") { hex = "#" + hex }
        guard let parsed = try? RGBA(hex: hex) else {
            draft = Self.text(color)
            return
        }
        if parsed != color { color = parsed }
        // `color` ở đây vẫn là giá trị cũ của ràng buộc: hiện mã vừa gõ, đã chuẩn hoá.
        draft = Self.text(parsed)
    }

    /// `#RRGGBB`, thêm `AA` khi không đặc.
    private static func text(_ color: RGBA) -> String {
        color.alpha == 255 ? String(color.hexString.prefix(7)) : color.hexString
    }
}

extension RGBA {
    fileprivate var swiftUIColor: Color {
        Color(
            .sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255,
            opacity: Double(alpha) / 255)
    }

    fileprivate init?(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> UInt8 { UInt8((min(max(value, 0), 1) * 255).rounded()) }
        self.init(
            red: byte(srgb.redComponent), green: byte(srgb.greenComponent), blue: byte(srgb.blueComponent),
            alpha: byte(srgb.alphaComponent))
    }
}
