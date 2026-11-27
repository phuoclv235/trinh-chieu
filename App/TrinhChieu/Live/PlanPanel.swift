import CoreModel
import SwiftUI
import UniformTypeIdentifiers

/// Chương trình buổi nhóm ở cột trái trên (mẫu `design/live.html`, `.plan-head` và `#plan`).
///
/// Bấm một mục: chọn và hiện lưới trang của mục ở giữa. Kéo thả để sắp xếp, kéo từ thư viện vào để thêm. `⌫` bỏ
/// mục đang chọn khỏi chương trình (không xoá bộ trình chiếu), `⌘Z` hoàn tác.
struct ServicePlanPanel: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prompt: TextPrompt?
    @State private var promptText = ""

    var body: some View {
        VStack(spacing: 0) {
            PlanHeader(onPrompt: show)
            Hairline()
            if let plan = environment.activePlan {
                if plan.items.isEmpty {
                    EmptyStateView(
                        systemImage: "text.badge.plus", title: "This service plan is empty",
                        message: "Double-click a song or media in the library below, or drag it here."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dropDestination(for: String.self) { values, _ in
                        insert(values, at: 0)
                    }
                } else {
                    PlanList(plan: plan, onPrompt: show, onDrop: insert)
                }
            } else {
                EmptyStateView(
                    systemImage: "list.bullet.rectangle", title: "No service plan yet",
                    message: "Create a plan for the coming Lord's Day, then add songs, Bible passages and media."
                ) {
                    Button {
                        environment.createPlan()
                    } label: {
                        Text("New service plan")
                    }
                    .buttonStyle(ControlButtonStyle(small: true))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: environment.library.map { ObjectIdentifier($0) }) {
            environment.openDefaultPlanIfNeeded()
        }
        .alert(prompt?.title ?? "", isPresented: isPrompting, presenting: prompt) { prompt in
            TextField(text: $promptText) { Text(prompt.title) }
            Button(prompt.confirm) { commit(prompt) }
                .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { prompt in
            if let message = prompt.message {
                Text(message)
            }
        }
    }

    private var isPrompting: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }

    private func show(_ prompt: TextPrompt) {
        promptText = prompt.initial
        self.prompt = prompt
    }

    private func commit(_ prompt: TextPrompt) {
        switch prompt.kind {
        case .addHeader: environment.addTextItem(header: true, text: promptText)
        case .addNote: environment.addTextItem(header: false, text: promptText)
        case .rename(let id): environment.setText(promptText, for: id)
        case .renamePlan: environment.renamePlan(promptText)
        case .startTime: environment.setPlannedStart(promptText)
        }
    }

    /// Thả dòng thư viện vào chương trình ở vị trí `index`.
    private func insert(_ values: [String], at index: Int) -> Bool {
        let items = values.compactMap { LibraryDrag.row(from: $0, environment: environment) }
            .compactMap { environment.planItem(for: $0) }
        environment.insertIntoPlan(items, at: index)
        return !items.isEmpty
    }
}

/// Hộp thoại hỏi một dòng chữ (thêm tiêu đề phần, ghi chú, đổi tên, đổi giờ bắt đầu).
struct TextPrompt {
    enum Kind {
        case addHeader
        case addNote
        case rename(UUID)
        case renamePlan
        case startTime
    }

    let kind: Kind
    let title: LocalizedStringKey
    let confirm: LocalizedStringKey
    var message: LocalizedStringKey?
    var initial = ""
}

/// Đầu khối chương trình: tên, ngày và giờ bắt đầu, chọn chương trình, nút "+".
private struct PlanHeader: View {
    let onPrompt: (TextPrompt) -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let plan = environment.activePlan
        HStack(alignment: .top, spacing: 8) {
            Menu {
                planMenu(current: plan)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(verbatim: plan?.title ?? String(localized: "Service plan"))
                            .font(Typography.columnTitle)
                            .tracking(-0.2)
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.text3)
                    }
                    if let plan {
                        Text(verbatim: subtitle(plan))
                            .font(Typography.numberSmall)
                            .foregroundStyle(Palette.text3)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .help(Text("Choose a service plan"))
            Spacer(minLength: 0)
            Menu {
                Button("Add section heading…") {
                    onPrompt(TextPrompt(kind: .addHeader, title: "Add section heading", confirm: "Add"))
                }
                Button("Add note…") {
                    onPrompt(TextPrompt(kind: .addNote, title: "Add note", confirm: "Add"))
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.text2)
                    .frame(width: Metrics.controlHeightSmall, height: Metrics.controlHeightSmall)
                    .background(RoundedRectangle(cornerRadius: Metrics.radius).fill(Palette.bgRaised))
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.radius).strokeBorder(Palette.lineStrong, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(plan == nil)
            .help(Text("Add a section heading or a note"))
            .accessibilityLabel(Text("Add item"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func planMenu(current: ServicePlan?) -> some View {
        let plans = (environment.library?.plans.values).map { Array($0) } ?? []
        ForEach(plans.sorted { ($0.date, $0.title) > ($1.date, $1.title) }) { plan in
            Button {
                environment.openPlan(plan.id)
            } label: {
                if plan.id == current?.id {
                    Label(plan.title, systemImage: "checkmark")
                } else {
                    Text(verbatim: plan.title)
                }
            }
        }
        if !plans.isEmpty {
            Divider()
        }
        Button("New service plan") {
            environment.createPlan()
        }
        if let current {
            Button("Rename…") {
                onPrompt(
                    TextPrompt(
                        kind: .renamePlan, title: "Rename service plan", confirm: "Rename", initial: current.title))
            }
            Button("Change start time…") {
                onPrompt(
                    TextPrompt(
                        kind: .startTime, title: "Planned start time", confirm: "Change",
                        message: "Hours and minutes, for example 8:50.",
                        initial: current.plannedStart.map(PlanSchedule.displayClock) ?? "9:00"))
            }
        }
    }

    /// "Chúa Nhật 29/11/2026 · bắt đầu 8:50".
    private func subtitle(_ plan: ServicePlan) -> String {
        var parts: [String] = []
        if let day = PlanSchedule.day(plan.date) {
            parts.append(LiveClock.dayText(day))
        }
        if let start = plan.plannedStart {
            parts.append(String(format: String(localized: "starts %@"), PlanSchedule.displayClock(start)))
        }
        return parts.joined(separator: " · ")
    }
}

/// Danh sách mục (kéo thả sắp xếp, nhận dòng thư viện kéo vào).
private struct PlanList: View {
    let plan: ServicePlan
    let onPrompt: (TextPrompt) -> Void
    let onDrop: ([String], Int) -> Bool
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let schedule = PlanSchedule(plan: plan)
        let nowIndex = Self.nowIndex(plan: plan, schedule: schedule, now: Date())
        List {
            ForEach(Array(plan.items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 0) {
                    if index == nowIndex {
                        NowLine()
                    }
                    PlanRow(item: item, start: schedule.starts[item.id], onPrompt: onPrompt)
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { offsets, destination in
                environment.movePlanItems(from: offsets, to: destination)
            }
            .dropDestination(for: String.self) { values, index in
                _ = onDrop(values, index)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    /// Vạch "bây giờ" nằm trước mục đầu tiên có giờ dự kiến sau lúc này (chỉ trong ngày nhóm).
    static func nowIndex(plan: ServicePlan, schedule: PlanSchedule, now: Date) -> Int? {
        guard let start = schedule.start, let end = schedule.end, Calendar.current.isDate(start, inSameDayAs: now),
            now >= start, now < end
        else { return nil }
        return plan.items.firstIndex { (schedule.starts[$0.id] ?? .distantPast) > now }
    }
}

/// Vạch giờ hiện tại (`.now-line`).
private struct NowLine: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ZStack(alignment: .trailing) {
                Rectangle().fill(Palette.late).frame(height: 1)
                Text(verbatim: LiveClock.shortTime(context.date))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.lateInk)
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Palette.late))
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(height: 17)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Now"))
            .accessibilityValue(Text(verbatim: LiveClock.shortTime(context.date)))
        }
    }
}

/// Một mục chương trình (`.row`): giờ dự kiến, biểu tượng loại, tiêu đề, dòng phụ, đèn đang chiếu, thời lượng.
private struct PlanRow: View {
    let item: ServicePlanItem
    let start: Date?
    let onPrompt: (TextPrompt) -> Void
    @Environment(AppEnvironment.self) private var environment
    @State private var isHovered = false

    var body: some View {
        let info = PlanItemInfo(item: item, environment: environment)
        let isSelected = environment.planEditing.selectedItemID == item.id
        let isLive = environment.livePlanItemID == item.id
        Group {
            if case .header(let header) = item {
                Text(verbatim: header.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .bottomLeading)
                    .padding(.leading, 16)
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
            } else {
                HStack(spacing: 8) {
                    Text(verbatim: start.map { LiveClock.shortTime($0) } ?? "")
                        .font(Typography.numberSmall)
                        .foregroundStyle(Palette.text2)
                        .frame(width: 38, alignment: .leading)
                    Image(systemName: info.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.text3)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: info.title)
                            .font(Typography.control)
                            .foregroundStyle(info.isMissing ? Palette.text3 : Palette.text)
                            .strikethrough(info.isMissing)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(verbatim: info.subtitle)
                            .font(Typography.small)
                            .foregroundStyle(info.isMissing ? Palette.late : Palette.text3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 6) {
                        if isLive {
                            Lamp(style: .breathing(Palette.accent))
                                .accessibilityLabel(Text("On screen"))
                        }
                        Text(verbatim: PlanSchedule.durationText(item.plannedDuration))
                            .font(Typography.numberSmall)
                            .foregroundStyle(Palette.text3)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 12)
                .padding(.vertical, 5)
                .frame(minHeight: 34)
            }
        }
        .background(isSelected ? Palette.accentSoft : (isHovered ? Palette.bgHover : Color.clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? Palette.accent : Color.clear).frame(width: 2)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            environment.selectPlanItem(item)
        }
        .help(Text(verbatim: info.title))
        .contextMenu { contextMenu }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var contextMenu: some View {
        switch item {
        case .header(let header):
            Button("Rename…") {
                onPrompt(
                    TextPrompt(kind: .rename(item.id), title: "Rename item", confirm: "Rename", initial: header.title))
            }
        case .note(let note):
            Button("Edit note…") {
                onPrompt(TextPrompt(kind: .rename(item.id), title: "Edit note", confirm: "Save", initial: note.text))
            }
        case .presentation, .scripture, .media:
            EmptyView()
        }
        Menu("Planned duration") {
            ForEach([1, 2, 3, 4, 5, 8, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                Button(String(format: String(localized: "%lld min"), minutes)) {
                    environment.setPlannedDuration(minutes: minutes, for: item.id)
                }
            }
            Divider()
            Button("No duration") {
                environment.setPlannedDuration(minutes: nil, for: item.id)
            }
        }
        Divider()
        Button("Remove from service plan") {
            environment.removePlanItem(item.id)
        }
    }
}

/// Tiêu đề, dòng phụ và biểu tượng của một mục chương trình.
@MainActor struct PlanItemInfo {
    var title: String
    var subtitle: String
    var symbol: String
    var isMissing = false

    init(item: ServicePlanItem, environment: AppEnvironment) {
        let library = environment.library
        let source = environment.activePlan.map { LiveSource.planItem(planID: $0.id, itemID: item.id) }
        let sequence = item.isLiveable ? environment.sequence(for: source) : nil
        let notFound = String(localized: "Not found")
        switch item {
        case .header(let header):
            title = header.title
            subtitle = ""
            symbol = "textformat"
        case .note(let note):
            title = note.text
            subtitle = String(localized: "Note")
            symbol = "text.alignleft"
        case .presentation(let entry):
            let presentation = library?.presentations[entry.presentationID]
            title = presentation?.title ?? notFound
            symbol = presentation?.kind == .generic ? "rectangle.stack" : "music.note"
            let kind = presentation?.kind == .generic ? String(localized: "Presentation") : String(localized: "Song")
            if let sequence {
                subtitle = kind + " · " + String(format: String(localized: "%lld slides"), sequence.slides.count)
            } else {
                subtitle = notFound
                isMissing = true
            }
        case .scripture(let entry):
            title = sequence?.title ?? entry.reference
            symbol = "book"
            let name = environment.translations.first { $0.code.lowercased() == entry.translation.lowercased() }?.name
            if sequence != nil {
                subtitle = String(localized: "Bible") + " · " + (name ?? entry.translation)
            } else {
                subtitle = notFound
                isMissing = true
            }
        case .media(let entry):
            let info = library?.media[entry.mediaID]
            title = info?.originalName ?? entry.mediaID.rawValue
            symbol = info?.kind == .image ? "photo" : info?.kind == .audio ? "waveform" : "film"
            if let info {
                var parts = [info.kind == .image ? String(localized: "Picture") : String(localized: "Video")]
                if let duration = info.duration {
                    parts.append(LibraryRows.duration(duration))
                }
                subtitle = parts.joined(separator: " · ")
            } else {
                subtitle = notFound
                isMissing = true
            }
        }
        if item.isLiveable && sequence == nil {
            isMissing = true
            subtitle = notFound
        }
    }
}

/// Kéo một dòng thư viện: chuỗi "trinhchieu:<loại>:<mã>" (bộ trình chiếu, media, Kinh Thánh).
enum LibraryDrag {
    static let prefix = "trinhchieu:"

    static func payload(for row: LibraryRow) -> String? {
        switch row.source {
        case .presentation(let id, _):
            return prefix + "presentation:" + id.uuidString
        case .media(let id):
            return prefix + "media:" + id.rawValue
        case .scripture(let translation, let reference):
            return prefix + "scripture:" + translation + "|" + reference
        case .planItem, nil:
            return nil
        }
    }

    @MainActor static func row(from payload: String, environment: AppEnvironment) -> LibraryRow? {
        guard payload.hasPrefix(prefix) else { return nil }
        let body = payload.dropFirst(prefix.count)
        guard let colon = body.firstIndex(of: ":") else { return nil }
        let kind = body[..<colon]
        let value = String(body[body.index(after: colon)...])
        switch kind {
        case "presentation":
            guard let id = UUID(uuidString: value), let presentation = environment.library?.presentations[id] else {
                return nil
            }
            return LibraryRows.row(for: presentation)
        case "media":
            guard let info = environment.library?.media[MediaID(value)] else { return nil }
            return LibraryRows.row(for: info)
        case "scripture":
            let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return LibraryRow(
                id: value, leading: .symbol("book"), title: parts[1], subtitle: parts[0],
                source: .scripture(translation: parts[0], reference: parts[1]))
        default:
            return nil
        }
    }
}
