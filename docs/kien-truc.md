# Kiến trúc

Bản tóm tắt kỹ thuật của kế hoạch đã duyệt (2026-11-26). Bản đầy đủ có phân tích phương án: [Kế hoạch kiến trúc phần mềm trình chiếu macOS](https://claude.ai/artifact/AdLpn5X4dR9YjvBy6C2mYu). Tệp này là **hợp đồng**: code phải theo đúng ranh giới ở đây. Muốn đổi ranh giới thì sửa tệp này trong cùng PR và nêu trong mô tả PR.

## 1. Quyết định đã chốt

| Chủ đề | Quyết định |
| --- | --- |
| Ngôn ngữ | Swift 6, bật strict concurrency ở mọi target |
| Nền tảng | macOS 15 trở lên, chỉ Apple Silicon (`arm64`) |
| Giao diện | SwiftUI cho khung, thanh bên, bảng thuộc tính, cài đặt. AppKit cho lưới trang chiếu (`NSCollectionView`), khung soạn trang, sau này là trình soạn bố cục LED và dòng thời gian |
| Dựng hình | Bộ trộn lớp tự viết trên Metal. Mỗi đầu ra một `CAMetalLayer` và một `CAMetalDisplayLink` riêng. Màu 8 bit sRGB, định dạng `bgra8Unorm`, trộn trong không gian gamma |
| Chữ | Core Text vẽ ra bitmap rồi đưa lên texture; viền, bóng, nền chữ làm bằng shader |
| Video | `AVPlayer` + `AVPlayerItemVideoOutput` (IOSurface) + `CVMetalTextureCache`. Tệp lạ chuyển mã lúc nhập (giai đoạn sau) |
| Âm thanh giai đoạn 1 | Âm thanh của media phát qua `AVPlayer.audioOutputDeviceUniqueID` (chọn thiết bị trong Cài đặt). Lõi âm thanh riêng (`AudioEngine`) để giai đoạn 3 |
| Lưu trữ | Tệp JSON trong thư mục thư viện + chỉ mục SQLite FTS5 dựng lại được. Chi tiết: `docs/dinh-dang-tep.md` |
| Tiến trình | Một tiến trình ở giai đoạn 0 đến 7. Ranh giới giao diện và lõi là lệnh và ảnh chụp trạng thái tuần tự hoá được, để giai đoạn 8 tách tiến trình mà không viết lại |
| Phân phối | Ngoài App Store, Developer ID, notarize |

## 2. Bốn tầng và quy tắc phụ thuộc

```
Tầng điều khiển   App (SwiftUI/AppKit), sau này: ControlServer, plugin, AI
        │ ShowCommand            ▲ ShowState (ảnh chụp)
        ▼                        │
Lõi điều phối     ShowController (CoreModel)
        │ RenderScene / StageScene
        ▼
Lõi thời gian thực RenderEngine (Metal), sau này AudioEngine
        ▲
Dịch vụ, dữ liệu  LibraryStore, LibraryIndex, Scripture, Importers
```

Quy tắc bắt buộc:

1. **Giao diện không gọi thẳng `RenderEngine`.** Mọi thao tác trực tiếp là một `ShowCommand` gửi tới `ShowController.send(_:)`. Giao diện chỉ đọc `ShowState`.
2. **`RenderEngine` không biết thư viện, bài hát, Kinh Thánh.** Nó chỉ nhận `RenderScene` (giá trị thuần mô tả cái cần vẽ) và trả khung hình. Mọi việc "nội dung này trông ra sao" do `SceneResolver` trong `CoreModel` làm.
3. **`TrinhChieuCore` không import AppKit, SwiftUI, Metal, AVFoundation, CoreText.** Nó phải build và test được trên Linux. Ngoại lệ duy nhất là mã đặt sau `#if canImport(...)` cho tiện ích không bắt buộc.
4. Lệnh và trạng thái là `Codable` và `Sendable`, tên lệnh ổn định (dùng cho remote và nhật ký về sau). Đổi tên một case là thay đổi phá vỡ: cần ghi trong mô tả PR.

## 3. Bản đồ module

| Đường dẫn | Target | Chạy trên | Nội dung |
| --- | --- | --- | --- |
| `Packages/TrinhChieuCore` | `VietText` | Linux, Mac | Gộp dấu tiếng Việt, chuẩn hoá Unicode, so khớp không dấu |
| | `CoreModel` | Linux, Mac | Mô hình dữ liệu (`Presentation`, `Theme`, `ServicePlan`...), `ShowCommand`, `ShowState`, `ShowController`, `SceneResolver`, `RenderScene`, mã hoá tệp và migration |
| | `Scripture` | Linux, Mac | Danh mục sách, phân tích địa chỉ câu, kho bản dịch (SQLite), chia câu thành trang |
| | `LibraryIndex` | Linux, Mac | Chỉ mục SQLite FTS5, tìm kiếm |
| | `LibraryStore` | Linux, Mac | Đọc ghi thư mục thư viện, theo dõi thay đổi, sao lưu, gói mang đi |
| | `Importers` | Linux, Mac | Văn bản lời bài hát, OpenLyrics, OSIS, USFM, Zefania |
| `Packages/TrinhChieuMedia` | `RenderEngine` | Mac | Thiết bị Metal, bộ trộn, dựng chữ, ảnh, video, chuyển cảnh, cửa sổ đầu ra, dựng ngoài màn hình để test |
| | `MediaImport` | Mac | Nhập PDF (PDFKit), tạo ảnh thu nhỏ, đọc thông tin video |
| `App` | `TrinhChieu` (ứng dụng) | Mac | Giao diện, cài đặt, bảng lệnh, nối `ShowController` với `RenderEngine` |

Phụ thuộc giữa target (mũi tên là "dùng"):

```
VietText    ← CoreModel
CoreModel   ← Scripture
Scripture   ← LibraryIndex ← LibraryStore
Scripture   ← Importers
CoreModel   ← RenderEngine
Mọi target  ← App
```

(Đọc "A ← B" là "B dùng A".)

`Scripture` dùng `CoreModel` vì `ScriptureReference` và chia trang trả về `Slide`. `LibraryIndex` dùng `Scripture` để lập chỉ mục câu. Không có phụ thuộc ngược.

## 4. Luồng và đồng thời

| Thành phần | Chạy ở đâu |
| --- | --- |
| Giao diện, `ShowController` | `@MainActor` |
| `RenderEngine` | Mỗi đầu ra có vòng `CAMetalDisplayLink` trên luồng riêng. Cảnh mới được giao qua một hộp thư khoá nhẹ (`OSAllocatedUnfairLock`), vòng vẽ lấy cảnh mới nhất mỗi khung |
| Dựng chữ (Core Text) | Hàng đợi nền, kết quả lưu đệm theo khoá nội dung; vòng vẽ không bao giờ chờ dựng chữ: chưa có thì vẽ khung trước |
| `LibraryStore`, `LibraryIndex` | `actor` riêng; đọc ghi đĩa không chạm luồng chính |

Nguyên tắc "không bao giờ đen màn": khi một nguồn lỗi (video hỏng, ảnh mất), lõi dựng hình giữ texture cuối của lớp đó và ghi log, không hiện màn đen hay chữ lỗi lên đầu ra. Lỗi chỉ hiện trên màn điều khiển.

## 5. Hợp đồng `RenderScene`

`RenderScene` là giá trị thuần, `Sendable`, `Equatable`, nằm ở `CoreModel`. Đây là tệp nguy hiểm: đổi nó là đổi cả hai phía.

```swift
public struct RenderScene: Sendable, Equatable {
    public var canvasSize: PixelSize          // kích thước khung vẽ của mẫu, ví dụ 1920x1080
    public var layers: [RenderLayer]          // theo thứ tự vẽ, dưới lên trên
    public var transition: TransitionSpec     // cách chuyển từ cảnh trước sang cảnh này
}

public enum LayerKind: String, Sendable, Codable, CaseIterable {
    case background, slide, overlay, message, mask   // giai đoạn 1 dùng background, slide
}

public struct RenderLayer: Sendable, Equatable {
    public var kind: LayerKind
    public var contentID: UUID                // đổi khi nội dung đổi; dùng để quyết định chuyển cảnh theo lớp
    public var items: [RenderItem]
}

public enum RenderItem: Sendable, Equatable {
    case color(RGBA, frame: PixelRect)
    case image(MediaRef, frame: PixelRect, fit: ContentFit)
    case video(VideoRef, frame: PixelRect, fit: ContentFit)
    case text(TextBlock, frame: PixelRect)
}
```

`TextBlock` mang chuỗi đã chuẩn hoá NFC, kiểu chữ đã giải xong (không còn tham chiếu tới mẫu), căn lề, quy tắc co chữ. `RenderEngine` chịu trách nhiệm đo và co chữ thật bằng Core Text. Đầy đủ các trường ở đặc tả task T0.5.

## 6. Thư viện ngoài đã duyệt

| Thư viện | Dùng cho | Giấy phép | Giai đoạn |
| --- | --- | --- | --- |
| GRDB | SQLite, FTS5 | MIT | 1 (có điều kiện, xem T1.1) |
| ZIPFoundation | Gói mang đi, đọc PPTX | MIT | 1 |
| Sparkle | Tự cập nhật | MIT | 8 |
| NDI SDK | NDI vào và ra | Có điều kiện | 3 |
| Blackmagic DeckLink SDK | Card capture, SDI | Có điều kiện | 3 |
| swift-protobuf | Đọc ProPresenter 7 | Apache 2.0 | 6 |
| WhisperKit hoặc tương đương | Nhận dạng giọng nói trên máy | MIT | 7 |

Công cụ phát triển (không đóng gói vào sản phẩm): **XcodeGen** để sinh dự án Xcode từ `App/project.yml`, cài bằng Homebrew trên máy Mac. Nếu Phuoc không cho phép, dùng phương án dự phòng ở T0.1.

Mọi thư viện khác: phải xin Phuoc (nêu tên, lý do, kích thước, phương án thay thế).
