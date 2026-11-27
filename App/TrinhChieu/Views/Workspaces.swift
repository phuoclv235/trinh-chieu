import SwiftUI

/// Chế độ Trực tiếp: ba cột theo mẫu `design/live.html`. T1.7 dựng khung và cột phải (xem trước, lớp giữ nhịp);
/// chương trình buổi nhóm, thư viện thu gọn và lưới trang chiếu làm ở T1.8.
struct LiveWorkspace: View {
    let showsRightRail: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                EmptyStateView(
                    systemImage: "list.bullet.rectangle",
                    title: "No service plan yet",
                    message: "Service plans and the compact library will appear in this column."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: Metrics.railLeft)
            .background(Palette.bgPanel)
            Hairline(vertical: true)
            EmptyStateView(
                systemImage: "rectangle.on.rectangle",
                title: "Nothing selected",
                message: "Choose an item in the service plan to see its slides here."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.bgStage)
            if showsRightRail {
                Hairline(vertical: true)
                ScrollView {
                    VStack(spacing: 0) {
                        OutputPreviewCard(role: .program)
                        Hairline()
                        OutputPreviewCard(role: .stage)
                        Hairline()
                    }
                }
                .scrollIndicators(.never)
                .frame(width: Metrics.railRight)
                .background(Palette.bgPanel)
                .transition(.move(edge: .trailing))
            }
        }
    }
}

/// Chế độ Soạn thảo: khung chờ trình soạn (T1.9).
struct EditorWorkspace: View {
    var body: some View {
        EmptyStateView(
            systemImage: "square.and.pencil",
            title: "Nothing to edit yet",
            message: "Choose a presentation in the library to edit its slides and lyrics."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgStage)
    }
}
