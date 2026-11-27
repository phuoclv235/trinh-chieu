import Foundation
import SwiftUI

/// Chế độ Trực tiếp: ba cột theo mẫu `design/live.html`. Trái: chương trình buổi nhóm và thư viện thu gọn; giữa:
/// lưới trang chiếu của nguồn đang xem; phải: xem trước, luồng tín hiệu, đồng hồ. Phím điều khiển nghe cho cả cửa sổ.
struct LiveWorkspace: View {
    let showsRightRail: Bool
    /// Mở chế độ Soạn thảo với một bộ trình chiếu.
    let onEdit: (UUID) -> Void
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { proxy in
                // Chương trình và thư viện chia cột theo tỉ lệ 1,2 : 1 như mẫu.
                let planHeight = (proxy.size.height * 1.2 / 2.2).rounded()
                VStack(spacing: 0) {
                    ServicePlanPanel()
                        .frame(height: planHeight)
                    Hairline()
                    CompactLibrary()
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: Metrics.railLeft)
            .background(Palette.bgPanel)
            Hairline(vertical: true)
            SlideStage(onEdit: onEdit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if showsRightRail {
                Hairline(vertical: true)
                LiveRightRail()
                    .frame(width: Metrics.railRight)
                    .background(Palette.bgPanel)
                    .transition(.move(edge: .trailing))
            }
        }
        .background {
            LiveKeyMonitor { key in environment.perform(key) }
        }
    }
}

/// Chương trình buổi nhóm (cột trái trên).
struct ServicePlanPanel: View {
    var body: some View {
        EmptyStateView(
            systemImage: "list.bullet.rectangle",
            title: "No service plan yet",
            message: "Service plans arrive in the next update. Pick songs from the library below for now."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
