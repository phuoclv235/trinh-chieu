# Đối chiếu tính năng với phần mềm cùng loại

Lập ngày 2026-11-28 theo câu hỏi của Phuoc. Đây là tài liệu **phân tích và đề xuất**, không phải đặc tả. Không mục nào ở đây được code cho tới khi Phuoc duyệt và có tệp task trong `plans/`. Kế hoạch các task đang chạy (giai đoạn 0, 1) không đổi.

Nguyên tắc: chỉ học **chức năng** và cách giải quyết vấn đề. Không chép giao diện, bố cục màn hình, tên gọi tính năng hay nhận diện của bất kỳ phần mềm nào. Tên các đề xuất bên dưới là tên tạm bằng tiếng Việt; tên chính thức phải qua `docs/thuat-ngu.md`.

## 1. Trả lời ngắn

**Đã tham khảo, nhưng chưa đủ.**

- Bản kế hoạch kiến trúc Phuoc duyệt ngày 2026-11-26 có mục "Đối chiếu ứng dụng tương tự" cho ProPresenter, vMix, OBS Studio, OpenLP, FreeShow và EasyWorship. Mục đó chỉ ở mức ý tưởng lớn (lấy gì, bỏ gì, làm khác gì), mỗi phần mềm một dòng.
- **Chưa từng đối chiếu** Resolume (Avenue, Arena), QLab và Millumin.
- **Chưa từng đối chiếu theo từng tính năng** với trang tính năng chính thức. Tài liệu này làm việc đó.

Kết quả: phần lõi của kế hoạch đứng vững. Trong hơn 100 tính năng đã rà, phần lớn đã có trong lộ trình hoặc thuộc loại nên cố ý bỏ. Có **19 chỗ thiếu đáng xét**, trong đó 8 chỗ tôi khuyến nghị ưu tiên cao vì rẻ và dùng được ngay mỗi Chúa Nhật (mục 4).

## 2. Nguồn đã đọc và giới hạn

Đọc ngày 2026-11-28. Phần nào không đọc được từ nguồn thì ghi rõ.

| Phần mềm | Nguồn | Giới hạn |
| --- | --- | --- |
| ProPresenter | [Trang toàn bộ tính năng](https://www.renewedvision.com/propresenter/all-features) (Phuoc gửi) | Trang liệt kê 43 tính năng. Bốn trang nhóm chỉ có tên, không có mô tả chi tiết |
| vMix | [Trang tính năng](https://www.vmix.com/software/features.aspx) (Phuoc gửi) | Đọc đủ |
| OBS Studio | [obsproject.com](https://obsproject.com/) | Trang chủ chỉ nêu 13 nhóm tính năng chính |
| Resolume | [Avenue và Arena](https://resolume.com/software/avenue-arena), [khác biệt hai bản](https://resolume.com/support/en/avenue-arena-difference) | Đọc đủ. "Arena" và "Resolume" trong câu hỏi là cùng một họ sản phẩm: Arena là bản đầy đủ của Resolume |
| QLab | [Wikipedia](https://en.wikipedia.org/wiki/QLab), [bài công bố QLab 5](https://groups.google.com/g/qlab/c/RgSWc-W8wNw), [tóm tắt QLab 5.3](https://www.usitt.org/news/qlab-releases-update-53) | Không tìm thấy trang tính năng chính thức trong kết quả tìm kiếm, nên dùng nguồn thứ cấp. Chờ trước, chờ sau và tự nối mục của QLab là theo hiểu biết chung của tôi, nguồn đã đọc không nêu |
| Millumin | [millumin.com](https://millumin.com/), [bắt đầu](https://help.millumin.com/docs/general/getting-started), [dòng thời gian](https://help.millumin.com/docs/playback/timeline/) | Chưa đọc các trang trợ giúp con (ghép mép, ánh xạ LED, nguồn vào) |

Giá và giấy phép của các phần mềm này không phải trọng tâm nên không đưa vào.

## 3. Mỗi phần mềm mạnh ở đâu và bài học cho Hệ thống

| Phần mềm | Sinh ra để làm gì | Bài học đáng lấy | Không hợp với ta |
| --- | --- | --- | --- |
| ProPresenter | Chiếu lời và Kinh Thánh cho Hội Thánh | Hành động gắn vào trang chiếu, vòng thông báo chạy riêng, chương trình mẫu, mốc trên video, lời nhắn lên màn hình nhắc, đồng hồ đủ loại | Dịch vụ thuê bao của Mỹ (Planning Center, MultiTracks, kho nền trả phí), ghép mép máy chiếu |
| vMix | Bàn trộn hình phát sóng trên Windows | Chỉnh màu từng nguồn vào, âm thanh theo hình, nhiều kênh lớp phủ độc lập, nút tắt tuỳ biến trên remote web | Phát lại chậm, vẽ lên hình, bảng tỉ số, đầu DVD |
| OBS Studio | Ghi hình và phát trực tiếp miễn phí | Phím tắt gán được cho mọi lệnh, xem nhiều cảnh cùng lúc | Giao diện tháo lắp nhiều khung, plugin mã gốc nạp thẳng |
| Resolume | Trình diễn hình theo nhạc (VJ) và ánh xạ sân khấu | Nguồn hình sinh bằng shader, cắt lát khung vẽ ra nhiều vùng LED | Đồng bộ nhịp DJ, hiệu ứng theo âm thanh, hơn trăm hiệu ứng |
| QLab | Điều khiển sân khấu kịch theo từng mục | Bảng bấm ngoài thứ tự, khoá tệp khi diễn, mờ dần là một lệnh, cảnh báo trước giờ diễn, phát sự kiện ra hệ thống khác | Âm thanh đối tượng 128 kênh, bàn đèn hơn nghìn loại đèn, bám mã thời gian |
| Millumin | Ánh xạ hình cho sân khấu và sắp đặt | Sửa mà khán giả không thấy, máy phát con chạy tự lập, gửi lệnh cho máy chiếu và camera | Dòng thời gian khoá hình, laser, cảm biến chuyển động, HDR 10 bit |

Nhận xét chung: không phần mềm nào trong sáu cái trên làm tốt cả hai việc chiếu lời và trộn hình, và không cái nào coi tiếng Việt là gốc. Đó vẫn là chỗ đứng riêng của Hệ thống.

## 4. Chỗ thiếu đáng thêm

Ước lượng công là của tôi, chưa có số đo. "Giai đoạn" là nơi nên đặt, theo lộ trình đã duyệt (2 đa đầu ra và LED, 2b đồng bộ nhiều máy, 3 nguồn vào và âm thanh, 4 Zoom, 5 remote, 7 AI, 8 mở rộng).

### 4.1 Ưu tiên cao: rẻ, dùng mỗi Chúa Nhật

| Mã | Đề xuất | Học từ | Ưu | Khuyết | Giai đoạn | Công |
| --- | --- | --- | --- | --- | --- | --- |
| ĐC1 | **Hành động theo trang.** Một trang chiếu mang theo việc cần làm khi nó lên màn: đổi cảnh đầu ra, xoá một lớp, chạy thao tác nhanh, tự sang trang sau N giây, lặp lại cả mục | ProPresenter, QLab | Một lần bấm làm đủ mọi thứ, đúng tinh thần "dòng chảy buổi nhóm". Tự sang trang và lặp là nền cho vòng thông báo (ĐC3) | Đổi định dạng tệp và `ShowCommand` (hai tệp nguy hiểm), cần migration. Dùng quá tay thì buổi nhóm khó đoán: phải hiện dấu rõ trên thẻ trang | 2 | 4 đến 5 ngày |
| ĐC2 | **Bảng bấm nhanh.** Một lưới nhỏ chứa những thứ hay dùng nhưng nằm ngoài chương trình: logo Hội Thánh, "Xin tắt chuông điện thoại", nhạc nền, đếm ngược, bài hát hay hát bất chợt | QLab | Cứu tình huống ngoài kịch bản mà không phải tìm. Dùng lại được cho Stream Deck và remote ở giai đoạn 5 | Trùng một phần với Bảng lệnh ⌘K. Cần chỗ trên màn điều khiển vốn đã chật: phải có mẫu `design/` duyệt trước | 2 | 3 ngày |
| ĐC3 | **Vòng trước giờ nhóm.** Một mục đặc biệt tự lặp ảnh, video thông báo và nhạc nền, kèm đếm ngược tới giờ bắt đầu; tới giờ thì tự dừng hoặc chờ bấm | ProPresenter | Việc mọi Hội Thánh làm mỗi tuần, hiện phải canh tay. Trên máy 3 màn không cần chạy song song như bản gốc, chỉ cần chạy trước giờ nhóm | Cần ĐC1 (tự sang trang, lặp) và đồng hồ (ĐC5). Chạy song song ra màn sảnh riêng thì để máy con ở giai đoạn 2b | 2 | 3 ngày sau ĐC1 |
| ĐC4 | **Chương trình mẫu.** Lưu khung một buổi (Chúa Nhật thường, Tiệc Thánh, Giáng Sinh) với tiêu đề phần, thời lượng dự kiến và mục cố định; mỗi tuần tạo chương trình mới từ khung | ProPresenter | Soạn chương trình còn vài phút. Rất rẻ vì `ServicePlan` đã có đủ dữ liệu | Thêm một loại tệp trong thư viện | 2, có thể kéo lên ngay sau MVP | 2 ngày |
| ĐC5 | **Chữ động và bộ đồng hồ đầy đủ.** Ô chữ chứa giá trị sống: giờ hiện tại, đếm ngược tới một giờ, đếm ngược theo thời lượng, đếm lên, thời gian video còn lại, tên mục kế tiếp, địa chỉ câu đang chiếu | ProPresenter, Millumin | Một cơ chế phục vụ cả đầu ra chính, lớp phủ và màn hình nhắc. Kế hoạch giai đoạn 2 mới ghi chung chung "đồng hồ" | Chữ đổi mỗi giây phải dựng lại texture: cần đo để không ăn ngân sách GPU dưới tải Zoom. Số phải dùng chữ số đều bề rộng để không nhảy | 2 | 4 ngày |
| ĐC6 | **Khoá khi đang nhóm.** Một công tắc: khi bật, không xoá, không kéo lệch thứ tự, không sửa nội dung chương trình được; chỉ còn thao tác chiếu | QLab | Người trực mới không lỡ tay phá chương trình giữa buổi. Rất rẻ | Người quen tay thấy vướng nếu mặc định bật: nên để tắt mặc định, nhắc bật khi tới giờ bắt đầu | 2 | 1 đến 2 ngày |
| ĐC7 | **Mờ dần khi xoá lớp.** Xoá lớp chữ, nền, âm thanh thì mờ dần theo thời gian đặt được, thay vì cắt ngay. Riêng `F1` (đen màn khẩn cấp) vẫn cắt tức thì | QLab, vMix | Hết cảnh nhạc nền tắt cụp. Phần hình dùng lại bộ chuyển cảnh sẵn có | Phần tiếng cần lõi âm thanh giai đoạn 3; trước đó chỉ hạ âm lượng `AVPlayer` | 2 (hình), 3 (tiếng) | 2 ngày |
| ĐC8 | **Mở rộng "Kiểm tra trước buổi nhóm"** (đề xuất 13 đang có ở `docs/de-xuat.md`): ngoài tải máy, quét cả chương trình để báo media thiếu, phông chữ thiếu, bản dịch chưa nhập, đầu ra chưa gắn, liên kết Slate hết hạn | QLab | Lỗi lộ ra tối thứ Bảy thay vì sáng Chúa Nhật. `WarningCenter` và `MediaLocator` đã có | Phải giữ danh sách kiểm ngắn, không thành bảng lỗi dài làm người dùng bỏ qua | 2 | 3 ngày |

### 4.2 Ưu tiên trung: có ích rõ, làm khi tới giai đoạn

| Mã | Đề xuất | Học từ | Ưu | Khuyết | Giai đoạn | Công |
| --- | --- | --- | --- | --- | --- | --- |
| ĐC9 | **Nền sinh bằng shader.** Vài kiểu nền chuyển động nhẹ do Hệ thống tự vẽ (chuyển màu chậm, hạt sáng, vân mờ), chỉnh màu theo mẫu trình bày, không cần tệp video | Resolume | Nhẹ máy hơn giải mã video khi Zoom đang chạy, lặp không lộ mối nối, và là chỗ tạo nét thẩm mỹ riêng không ai có sẵn | Thêm loại `RenderItem` (tệp nguy hiểm). Phải thiết kế tiết chế, vài kiểu thật đẹp, không thành kho hiệu ứng | 2 | 5 ngày |
| ĐC10 | **Mốc trên video.** Đặt mốc tại thời điểm trong video để chạy thao tác nhanh, gửi lời nhắn lên màn hình nhắc ("còn 30 giây"), hoặc tự sang mục kế khi hết | ProPresenter | Ban hát và người giảng biết khi nào video hết mà không cần người trực báo | Cần giao diện đặt mốc trên thanh thời gian video | 3 | 3 ngày |
| ĐC11 | **Chỉnh hình cơ bản cho từng nguồn vào.** Cân trắng, sáng, tương phản, bão hoà, cắt vùng, lật | vMix | Camera rẻ và ánh sáng hội trường hiếm khi đúng màu. Làm bằng shader, gần như không tốn GPU | Không làm máy đo sóng hay bánh xe màu: chỉ vài thanh trượt | 3 | 3 ngày |
| ĐC12 | **Máy dự phòng nóng.** Một nút trình chiếu giữ sẵn chương trình và trạng thái; máy chủ treo thì nút đó nhận quyền điều khiển trong vài giây | ProPresenter, Millumin | Đúng nguyên tắc "không bao giờ đen màn" ở mức cả máy. Hợp đồng `RenderScene` có `revision` đã chuẩn bị sẵn | Phải đồng bộ cả thư viện soạn chứ không chỉ cảnh; quy tắc ai làm chủ khi cả hai còn sống dễ sai | Sau 2b | 1 đến 2 tuần |
| ĐC13 | **Phím tắt gán được, chung một bảng với MIDI và Stream Deck.** Mọi `ShowCommand` và thao tác nhanh gán được vào phím, nốt MIDI hay nút cứng qua cùng một màn | OBS, vMix | Làm một lần dùng cho ba loại thiết bị. Bàn phím phụ rẻ thành bàn điều khiển | Xung đột phím với ô gõ chữ phải xử lý kỹ | 5 | 4 ngày |
| ĐC14 | **Phát sự kiện và gửi lệnh ra thiết bị.** API điều khiển không chỉ nhận lệnh mà còn phát sự kiện (mục lên màn, trang đổi) qua WebSocket và OSC; thao tác nhanh gửi được lệnh ra ngoài: bật tắt máy chiếu (PJLink), gọi vị trí nhớ của camera quay quét, đổi cảnh đèn qua OSC hoặc MIDI | QLab, Millumin, ProPresenter | Một lần bấm "Bắt đầu buổi nhóm" bật máy chiếu và đưa camera về vị trí. Không phải viết bàn đèn | Mỗi giao thức là một khối kiểm thử với thiết bị thật Phuoc phải có. Nên làm khung chung, thêm từng giao thức khi có thiết bị | 5 | 5 ngày khung, mỗi giao thức 1 đến 2 ngày |

### 4.3 Ưu tiên thấp: chỉ làm khi có nhu cầu thật

| Mã | Đề xuất | Học từ | Ưu | Khuyết | Giai đoạn |
| --- | --- | --- | --- | --- | --- |
| ĐC15 | **Đầu ra có kênh trong suốt** (NDI kèm alpha; cặp hình và khoá qua card SDI) | ProPresenter | Bàn trộn hình ngoài đè chữ của ta lên camera sạch nét | Chỉ cần khi Hội Thánh có bàn trộn hình rời. Cặp SDI phụ thuộc đề xuất 12 (card xuất hình) | 3 |
| ĐC16 | **Chia sẻ hình cho ứng dụng khác trên cùng máy qua Syphon** | ProPresenter, Resolume, QLab | Đưa hình sang OBS hay phần mềm khác không tốn mã hoá | Thư viện ngoài chưa duyệt. Camera ảo ở giai đoạn 4 đã phủ phần lớn nhu cầu | 3 |
| ĐC17 | **Ghi nhịp chuyển trang.** Bấm theo một bản nhạc thu sẵn một lần, lần sau Hệ thống tự chuyển đúng nhịp | ProPresenter | Bài hát đặc biệt có nhạc thu sẵn chạy không cần người bấm | Ít dùng. Nên làm chung với "dò theo lời hát" của giai đoạn 7 | 7 |
| ĐC18 | **Phát trực tiếp thẳng lên YouTube hoặc Facebook** (RTMP, SRT) | vMix, OBS | Bỏ được OBS nếu Hội Thánh có phát trực tiếp | Mã hoá liên tục ăn CPU và GPU trên Mac mini M4 base đang chạy Zoom. Kế hoạch gốc để ngoài lộ trình chính | Cần Phuoc quyết (mục 7) |
| ĐC19 | **Xuất bộ trình chiếu ra ảnh hoặc PDF** | Millumin | Gửi lời bài hát cho ban hát, in tờ chương trình | Ít giá trị cho việc chiếu | 6 |

## 5. Bảng đối chiếu đầy đủ

Cột "Kế hoạch" ghi giai đoạn đã có trong lộ trình duyệt ngày 2026-11-26. Viết tắt: PP ProPresenter, VM vMix, OBS, RS Resolume, QL QLab, ML Millumin.

### 5.1 Nội dung và soạn thảo

| Tính năng | Ai có | Kế hoạch | Nhận định |
| --- | --- | --- | --- |
| Thư viện bài hát, thứ tự hát tách khỏi lời | PP | Có, giai đoạn 1 (xong) | Đủ |
| Soạn lời dạng văn bản, trang cập nhật theo | PP | Có, T1.9 | Đủ |
| Sửa nhanh chữ khi đang chiếu | PP | Có một phần: sửa khi đang chiếu không giật | Nên cho sửa tại chỗ ngay trên thẻ trang ở chế độ Trực tiếp; xét cùng ĐC6 |
| Mẫu trình bày, đổi một lần cho cả bài | PP | Có, giai đoạn 1 | Ta hơn: mỗi đầu ra một mẫu cho cùng nội dung |
| Kinh Thánh gõ là ra, song song hai bản dịch | (EasyWorship) | Có, giai đoạn 1 | Ta hơn: địa chỉ tiếng Việt viết tắt, không dấu |
| Tìm một ô cho mọi thứ | PP, ML | Có, Bảng lệnh ⌘K | Đủ |
| Hình khối, chữ, ảnh, video trong trang | PP | Có, T1.9 | Đủ. Nguồn trực tiếp trong hình khối ở giai đoạn 3 |
| Chữ động, đồng hồ trong trang | PP, ML | Một phần ("đồng hồ", giai đoạn 2) | **Thiếu chi tiết: ĐC5** |
| Hiệu ứng chữ và nền | PP, RS | Viền, bóng, nền chữ bằng shader | Đủ. Không chạy theo kho hiệu ứng |
| Nền chuyển động không cần tệp | RS | Không | **Thiếu: ĐC9** |
| Lớp web HTML | VM, OBS, ML | Có, giai đoạn 8 | Đủ. Trang tương tác hội chúng ở giai đoạn 4 dựng gốc, không cần chờ lớp web |
| Nhập PPTX, tệp ProPresenter, SongSelect | PP, VM | Có, giai đoạn 6 | Đủ |
| Kho nền và nhạc trả phí tích hợp | PP | Không | Cố ý bỏ (mục 6) |
| Đồng bộ thư viện giữa nhiều máy | PP (đám mây), ML | Thư mục đồng bộ và giữ bản xung đột (đề xuất 3, 8) | Đủ, không cần máy chủ |
| Nhiều người cùng sửa một tệp theo thời gian thực | QL | Không | Cố ý bỏ |

### 5.2 Chương trình buổi nhóm và điều khiển trực tiếp

| Tính năng | Ai có | Kế hoạch | Nhận định |
| --- | --- | --- | --- |
| Danh sách mục theo thứ tự, bấm là lên | PP, QL, ML | Có, giai đoạn 1 | Ta hơn: giờ dự kiến và giờ thật, Nhật ký buổi nhóm |
| Chương trình mẫu | PP | Không | **Thiếu: ĐC4** |
| Hành động gắn vào trang, tự sang trang, lặp | PP, QL, ML | Chỉ ở mức mục ("thao tác nhanh khi vào mục") | **Thiếu ở mức trang: ĐC1** |
| Thao tác nhanh (gộp nhiều lệnh một nút) | PP | Có tên trong bảng thuật ngữ, chưa gán giai đoạn | Cần gán: đề nghị giai đoạn 2, làm cùng ĐC1 |
| Vòng thông báo chạy riêng, hẹn lịch | PP | Không | **Thiếu: ĐC3.** Hẹn lịch theo ngày để sau |
| Lưới bấm ngoài thứ tự | QL | Không | **Thiếu: ĐC2** |
| Xoá từng lớp độc lập | PP | Có, giai đoạn 1 | Đủ |
| Mờ dần khi xoá, mờ dần là một lệnh | QL, VM | Không rõ | **Thiếu: ĐC7** |
| Tập dượt, xem trước rồi mới phát | QL, OBS, VM, ML | Có: Tập dượt, Đóng băng | Đủ. Xem trước và phát cho camera ở giai đoạn 3 |
| Khoá tệp khi đang chạy | QL | Không | **Thiếu: ĐC6** |
| Cảnh báo trước giờ chạy, nối lại media mất | QL | Một phần (`WarningCenter`, đề xuất 13) | **Mở rộng: ĐC8** |
| Tự lưu và ảnh chụp phiên bản | QL | Có: tự lưu, `.bak`, thùng rác | Đủ |
| Chỉ số khung hình trên màn điều khiển | QL | Có: chỉ báo khung hình | Đủ |
| Dòng thời gian ghi nhịp rồi phát lại | PP | Không | Thấp: ĐC17 |
| Dòng thời gian khoá hình, đoạn lặp | ML | Không | Cố ý bỏ |
| Mốc trên video | PP | Không | **Thiếu: ĐC10** |

### 5.3 Đầu ra, màn LED và màn hình nhắc

| Tính năng | Ai có | Kế hoạch | Nhận định |
| --- | --- | --- | --- |
| Nhiều đầu ra, lớp nào ra đầu ra nào | PP, VM, RS, ML | Có, giai đoạn 2 (Cảnh đầu ra) | Đủ |
| Khung vẽ kích thước tuỳ ý, cắt lát ra nhiều vùng | RS, ML | Có, giai đoạn 2 | Đủ. Đúng nhu cầu LED qua bộ xử lý |
| Kéo bốn góc, mặt nạ, ảnh thử | PP, RS, ML | Có, giai đoạn 2 | Đủ |
| Ghép mép nhiều máy chiếu, uốn lưới | PP, RS, ML | Không | Cố ý bỏ |
| Màn hình nhắc tuỳ biến, trang hiện tại và kế | PP | Có, cơ bản ở 1, tuỳ biến ở 2 (đề xuất 15) | Đủ |
| Lời nhắn riêng lên màn hình nhắc | PP | Có, giai đoạn 2 | Đủ |
| Hình đầu ra chính hiện trên màn hình nhắc | PP | Một phần (khối "hình camera") | Thêm khối "hình đầu ra chính" khi làm đề xuất 15, công nhỏ |
| Lớp phủ: logo, tên diễn giả, nhiều kênh độc lập | PP, VM | Có, giai đoạn 2 | Nên cho nhiều lớp phủ bật tắt độc lập; `RenderScene.layers` là mảng nên hợp đồng không cản |
| Chạy chữ, bảng tỉ số | VM | Thông báo ở giai đoạn 2 | Chạy chữ thông báo: đủ. Bảng tỉ số: bỏ |
| Xem nhiều nguồn, nhiều đầu ra một lúc | PP, VM, OBS | Xem trước từng đầu ra (1), nhiều nguồn (3) | Đủ |
| Đầu ra có kênh trong suốt | PP | Không | Thấp: ĐC15 |
| NDI, SDI ra | PP, VM, RS, QL | Có, giai đoạn 3 | Đủ |
| Syphon | PP, RS, QL | Không | Thấp: ĐC16 |
| HDR, 10 bit, 16K | ML | Không (đã chốt 8 bit sRGB) | Cố ý bỏ |
| Đèn DMX, dải LED điểm ảnh, laser | RS, QL, ML | Không | Cố ý bỏ; chỉ gửi lệnh đổi cảnh đèn (ĐC14) |

### 5.4 Nguồn vào, trộn hình, âm thanh

| Tính năng | Ai có | Kế hoạch | Nhận định |
| --- | --- | --- | --- |
| Camera, card thu hình, NDI vào, chụp cửa sổ | PP, VM, OBS, RS, QL, ML | Có, giai đoạn 3 | Đủ |
| Hình trong hình, nhiều ô, khoá màu | VM, OBS | Có, giai đoạn 3 | Đủ |
| Chỉnh màu từng nguồn | VM | Không | **Thiếu: ĐC11.** Máy đo sóng: bỏ |
| Chuyển cảnh nhiều kiểu, chuyển cảnh bằng video | VM, OBS, ML | Hoà tan, shader pha | Đề nghị bộ nhỏ có chủ đích (cắt, hoà tan, trượt, mờ qua màu), không làm 13 kiểu |
| Bộ trộn âm: mức, tắt, trễ, EQ, nén | VM, OBS | Có, giai đoạn 3 | Đủ. Thêm cổng ồn cho micro, công nhỏ |
| Âm thanh theo hình | VM | Có, giai đoạn 3 | Đủ |
| Ma trận định tuyến, mix-minus cho Zoom | VM, QL, ML | Có, giai đoạn 3 và 4 | Đủ |
| Plugin âm thanh ngoài (VST, AudioUnit) | OBS, RS, QL | Không | Để ngỏ, không đưa vào lộ trình |
| Âm thanh đối tượng, 128 kênh, 5.1 | QL, ML | Không | Cố ý bỏ |
| Ghi hình | VM, OBS | Có, giai đoạn 3 | Đủ. Nhật ký buổi nhóm đánh dấu chương là nét riêng |
| Phát trực tiếp RTMP, SRT | VM, OBS, PP (Resi) | Tuỳ chọn, ngoài lộ trình | Cần Phuoc quyết: ĐC18 |
| Phát lại chậm, vẽ lên hình | VM | Không | Cố ý bỏ |

### 5.5 Zoom, nhiều máy, điều khiển ngoài, mở rộng

| Tính năng | Ai có | Kế hoạch | Nhận định |
| --- | --- | --- | --- |
| Camera ảo | VM, OBS | Có, giai đoạn 4 (làm sớm được: đề xuất 5) | Đủ |
| Nhận từng người trên Zoom thành nguồn riêng | VM | Chụp cửa sổ Zoom; Zoom SDK để ngỏ | Giữ như kế hoạch. vMix cho thấy đường SDK khả thi nếu chụp cửa sổ không đủ |
| Gọi khách qua trình duyệt, không cần Zoom | VM | Không | Cố ý bỏ |
| Nhiều máy nối mạng cùng chiếu | PP, ML | Có, giai đoạn 2b | Ta hơn: đồng bộ theo khung bằng đồng hồ chung, media từ NAS |
| Máy dự phòng nhận quyền điều khiển | PP, ML | Không | Trung: ĐC12 |
| API điều khiển | PP, RS, QL, ML | Có, giai đoạn 5 | Thêm phát sự kiện ra: ĐC14 |
| Remote web, nút tắt tuỳ biến | VM, QL | Có, giai đoạn 5 | Nút tắt lấy từ Bảng bấm nhanh (ĐC2) |
| MIDI, OSC, Stream Deck | PP, RS, QL, ML | Có, giai đoạn 5 | Đủ. Gộp cơ chế gán: ĐC13 |
| Phím tắt gán được cho mọi lệnh | OBS, VM | Phím cố định | Trung: ĐC13 |
| Gửi lệnh cho máy chiếu, camera, bàn trộn | ML, PP | Không | Trung: ĐC14 |
| Mã thời gian (LTC, MTC) | PP, RS, QL, ML | Không | Cố ý bỏ |
| Kịch bản JavaScript | ML (QLab: AppleScript; OBS: Lua, Python) | Có, giai đoạn 8 | Đủ |
| Plugin mã gốc | OBS, RS | Không nạp mã gốc của bên thứ ba | Giữ quyết định: plugin lỗi không được làm đen màn |
| Phụ đề | QL (mục chữ) | Có, giai đoạn 7 (phụ đề trực tiếp bằng AI) | Ta hơn |

## 6. Cố ý bỏ và vì sao

| Tính năng | Có ở | Lý do bỏ | Khi nào xét lại |
| --- | --- | --- | --- |
| Ghép mép máy chiếu, uốn lưới, ánh xạ lên vật thể | PP, RS, ML | Hội trường dùng LED qua bộ xử lý và máy chiếu phụ lặp hình. Kéo bốn góc và mặt nạ ở giai đoạn 2 là đủ | Khi có hội trường ghép hai máy chiếu thành một màn rộng |
| Đồng bộ nhịp DJ, hiệu ứng theo âm thanh, kho hiệu ứng | RS | Dành cho trình diễn hình theo nhạc. Trong buổi nhóm, hình nhảy theo nhạc làm phân tâm khỏi lời | Không dự kiến |
| Bàn đèn DMX, dải LED điểm ảnh, laser | RS, QL, ML | Là một sản phẩm khác. Hội Thánh có bàn đèn riêng; ta chỉ gửi lệnh đổi cảnh (ĐC14) | Không dự kiến |
| Mã thời gian LTC, MTC | PP, RS, QL, ML | Chỉ cần khi chạy theo nhạc nền dựng sẵn từng khung. Buổi nhóm đi theo người, không theo băng | Khi có chương trình Giáng Sinh dàn dựng với nhạc nền khoá sẵn |
| Dòng thời gian khoá hình, dựng hoạt cảnh | ML | Đây là việc của phần mềm dựng phim. Video dựng sẵn nhập vào là xong | Không dự kiến |
| Phát lại chậm, vẽ lên hình, bảng tỉ số | VM | Dành cho thể thao | Không dự kiến |
| Gọi khách qua trình duyệt riêng | VM | Zoom đã làm việc này và Hội Thánh đã quen | Nếu Zoom đổi điều khoản |
| Âm thanh đối tượng, vòm, 128 kênh | QL, ML | Hội trường có bàn trộn âm riêng. Lõi âm thanh của ta chỉ lo media, Zoom và bản ghi | Không dự kiến |
| HDR, 10 bit | ML | Bộ xử lý LED nhận HDMI 8 bit; đã chốt 8 bit sRGB để nhẹ máy | Khi phần cứng đầu ra đổi |
| Dịch vụ thuê bao Mỹ: Planning Center, MultiTracks, kho nền trả phí, phát trực tiếp Resi | PP | Hội Thánh Việt Nam gần như không dùng; ràng buộc tài khoản và phí | Nếu thương mại hoá ra nước ngoài |
| Báo cáo bài hát tự động cho CCLI | PP | Chưa áp dụng ở Việt Nam. Nhật ký buổi nhóm đã ghi đủ bài nào dùng khi nào để tự xuất báo cáo | Nếu cần báo cáo bản quyền |
| Cảm biến chuyển động, bo mạch Arduino | ML | Dành cho sắp đặt tương tác | Không dự kiến |
| Giao diện tháo lắp nhiều khung và cửa sổ | OBS, PP | Trái hướng "Bàn trộn" một màn đã duyệt ở T0.3; dễ lạc khi đang nhóm | Không dự kiến |
| Plugin mã gốc nạp thẳng vào ứng dụng | OBS, RS | Plugin lỗi làm sập buổi chiếu. Đã chốt ba tầng an toàn | Không dự kiến |
| Nhiều người cùng sửa một tệp theo thời gian thực | QL | Cần hạ tầng đồng bộ riêng; thư mục đồng bộ và màn xử lý xung đột (đề xuất 8) đủ cho đội vài người | Khi đội soạn trên 3 người làm cùng lúc |

## 7. Nét riêng cần giữ

Rà xong sáu phần mềm, các điểm sau **không cái nào có đủ**, nên là chỗ đầu tư để Hệ thống độc bản thay vì chạy theo số lượng tính năng:

1. Tiếng Việt là gốc: tìm không dấu, địa chỉ câu viết tắt, ngắt dòng theo cụm từ, khoảng dòng cho dấu chồng.
2. Gõ là lên màn bằng Bảng lệnh, ba bước cho một câu Kinh Thánh.
3. Chương trình buổi nhóm có giờ dự kiến, giờ thật và Nhật ký buổi nhóm.
4. Đồng bộ nhiều máy theo khung, mỗi máy tự dựng hình ở chất lượng gốc.
5. Bền dưới tải thật (Zoom và web cùng chạy) có tiêu chí đo.
6. Một bàn điều khiển cho cả chiếu lời lẫn trộn hình.

Các đề xuất ĐC1 đến ĐC9 được chọn vì chúng **làm dày thêm** các nét này (nhất là số 3 và 5), không kéo sản phẩm sang hướng VJ hay sân khấu kịch.

## 8. Việc cần Phuoc quyết

1. **Duyệt nhóm ưu tiên cao (ĐC1 đến ĐC8) vào giai đoạn 2?** Tổng khoảng 22 đến 24 ngày công theo ước lượng của tôi, tức giai đoạn 2 dài thêm 4 đến 5 tuần nếu làm hết. Phương án gọn: chỉ lấy ĐC1, ĐC3, ĐC4, ĐC6 (khoảng 10 đến 12 ngày), phần còn lại xếp sau.
2. **ĐC4 (chương trình mẫu) và ĐC6 (khoá khi đang nhóm) có kéo lên ngay sau MVP không?** Hai mục này rẻ và không phụ thuộc đa đầu ra.
3. **Hội Thánh có phát trực tiếp lên YouTube hoặc Facebook không, hay chỉ Zoom?** Câu trả lời quyết định ĐC18.
4. **Hội Thánh có bàn trộn hình rời, camera quay quét hay máy chiếu điều khiển qua mạng không?** Quyết định ĐC14 và ĐC15 làm giao thức nào trước.

Khi Phuoc duyệt mục nào, mục đó được viết thành tệp task trong `plans/` (Fable 5.2 đặc tả, Opus 5.5 code) và các tính năng có giao diện phải qua mẫu `design/` trước.
