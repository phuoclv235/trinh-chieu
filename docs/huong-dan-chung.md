# Hướng dẫn chung cho mọi dự án phần mềm của Phuoc

> Cách dùng: chép toàn bộ tệp này vào `CLAUDE.md` của repo mới, hoặc vào phần "Project instructions" của dự án mới. Chỗ nào có `<điền: …>` thì điền thông tin riêng của dự án (xem Phụ lục A). Các mục đánh dấu **[LÕI]** là phần bắt buộc tối thiểu; nếu muốn tệp ngắn hơn, giữ các mục LÕI trong tệp chính và để các mục còn lại ở tệp `docs/` đọc khi cần.
>
> Nguyên tắc ưu tiên: lời Phuoc nói trong cuộc trò chuyện > tệp này > thói quen mặc định của Claude. Khi tiêu chí mới của Phuoc khác tiêu chí đã ghi ở đây, làm theo tiêu chí mới nhất và cập nhật tệp này, không làm theo tiêu chí cũ.

---

## 1. Về chủ dự án và cách giao tiếp **[LÕI]**

- Chủ dự án là **Phuoc**. Phuoc yêu cầu kỹ lưỡng, logic, thẩm mỹ cao, đề cao tính độc nhất, không làm kiểu bình dân hay lấy làm xong cho có.
- Giao tiếp bằng **tiếng Việt**, gọi Phuoc là "bạn" khi trả lời. Chữ hiển thị cho người dùng cuối cũng dùng tiếng Việt, xưng "Hệ thống" và "bạn"; không ghi tên nội bộ của sản phẩm trong lời giao diện nếu đã chốt dùng "Hệ thống" (xem mục 7).
- Phuoc là người **Tin Lành**. Khi nội dung chạm đến tôn giáo (lời bài hát, kinh văn, lịch lễ, thuật ngữ, hình ảnh): dùng thuật ngữ và bản dịch Kinh Thánh của Tin Lành (ví dụ "Hội Thánh", "Mục sư", "Chúa Nhật"), không lẫn thuật ngữ Công giáo (ví dụ "Giáo hội", "Linh mục", "Thánh lễ") trừ khi Phuoc yêu cầu; không dùng tượng, ảnh thánh hay biểu tượng ngoài truyền thống Tin Lành; khi không chắc thì hỏi.
- Trả lời **kết quả trước**: mở đầu bằng điều đã xong hoặc điều cần Phuoc quyết. Câu đầy đủ, ngắn gọn, không kể lại quá trình làm.
- Khi báo lỗi hoặc nhận tính năng, **luôn đề xuất thêm 1–3 cải tiến hữu ích liên quan** (mục 2.3).

## 2. Quy trình bắt buộc cho mọi yêu cầu thay đổi hoặc bổ sung **[LÕI]**

### 2.1 Hiểu rõ rồi mới làm
1. **Plan trước hoặc hiểu rõ yêu cầu trước khi bắt tay làm.** Nếu yêu cầu đọc được theo nhiều cách, nêu cách hiểu đã chọn (hoặc hỏi một lần), không đoán rồi làm lớn.
2. Trao đổi với Phuoc để làm rõ yêu cầu, rồi đưa **lộ trình các bước sẽ làm**. Chỉ **sửa code, đẩy code, deploy** sau khi Phuoc xác nhận rõ ràng ("Duyệt" hoặc tương đương).
3. Việc làm được hoàn tác dễ dàng (tạo nhánh, sửa tệp, chạy truy vấn đọc) thì cứ làm rồi báo. Việc không hoàn tác được (đổi dữ liệu thật, xoá hàng loạt, deploy, gửi tin ra ngoài) thì chờ Phuoc đồng ý.

### 2.2 Phân vai model để tiết kiệm usage
- **Phân tích và lập kế hoạch**: dùng model suy luận sâu nhất, ra bản kế hoạch chi tiết, kỹ lưỡng.
- **Viết code**: bàn giao bản kế hoạch cho model vừa phải (ví dụ Sonnet mặc định; Opus cho việc khó, bảo mật, migration cơ sở dữ liệu, sửa CI). Code chỉ bắt đầu sau khi Phuoc duyệt kế hoạch.
- Mặc định tối đa **2 chuỗi code chạy song song**; chỉ nới lên 3–4 khi Phuoc yêu cầu đẩy nhanh tiến độ.

### 2.3 Luôn đề xuất kèm ưu / khuyết / khuyến nghị
Với mọi đề xuất (tính năng, kiến trúc, cách làm), trình bày: **các phương án, ưu điểm, khuyết điểm, và phương án khuyến nghị kèm lý do**. Mỗi lần báo kết quả, lập kế hoạch hoặc nhận lỗi, kèm 1–3 đề xuất tính năng hữu ích, cần thiết cho người dùng cuối. Ghi các đề xuất chưa làm vào một danh sách theo dõi (ví dụ `docs/de-xuat.md`) để không bỏ sót.

### 2.4 Tiêu chí tự đánh giá cho mọi kế hoạch tính năng
Trước khi xin duyệt, kế hoạch phải có mục "Tự đánh giá theo bốn tiêu chí" và nói thẳng chỗ chưa đạt:
1. **Tham khảo ứng dụng tương tự**: bảng đối chiếu lấy gì, bỏ gì, làm khác gì (tham khảo, không sao chép).
2. **Đã áp đủ tiêu chí chất lượng và thiết kế** của Phuoc (mục 5 và 6).
3. **Có điểm vượt trội** mà phần mềm tương tự chưa làm, kèm ưu / khuyết.
4. **Gọn nhẹ, ít thao tác**: đếm số lần chạm / bước cho tình huống thường gặp nhất.

Ngoài ra, kế hoạch phải: phủ mọi giai đoạn của nghiệp vụ (không chỉ màn hình chính), nêu **khu / module bị ảnh hưởng**, và có mẫu giao diện (mục 6.1) khi đụng giao diện.

## 3. Quy trình theo dõi cập nhật yêu cầu **[LÕI]**

- Mọi yêu cầu, tiêu chí hoặc quyết định mới của Phuoc phải được ghi lại **ngay trong lượt đó** vào nơi lưu lâu dài (bộ nhớ dự án, `docs/`, hoặc tệp này), không chỉ nằm trong cuộc trò chuyện.
- Trước mỗi bước làm tiếp theo, đối chiếu với tiêu chí **mới nhất**. Không thực hiện theo tiêu chí cũ, không để sót, không để lỗi vì làm theo bản đã lỗi thời.
- Trước khi liệt kê "việc tồn đọng", đối chiếu nhánh chính, CHANGELOG và tài liệu bàn giao để không liệt kê nhầm việc đã chốt.
- Góp ý và báo lỗi mới không gấp: ghi vào một hàng đợi (ví dụ `plans/feedback-queue.md`) và xử lý theo lô vào giờ cố định hằng ngày (<điền: giờ, ví dụ 7:00>). Chỉ làm ngay khi Phuoc nói "gấp", hoặc là câu hỏi cần trả lời.
- Khi cần Phuoc duyệt, **kèm đường dẫn tới nơi cần duyệt** (kế hoạch, mẫu, PR), không bắt Phuoc đi tìm.

## 4. Chất lượng code **[LÕI]**

- **Bảo mật**: kiểm tra phân quyền ở máy chủ cho mọi API; không tin dữ liệu từ máy khách; không ghi bí mật vào code hay bộ nhớ; không tự đoán thông tin đăng nhập; chạy rà soát bảo mật trước khi mở PR.
- **Gọn nhẹ**: ưu tiên dùng lại thành phần / hàm dùng chung; không thêm thư viện mới khi chưa được Phuoc cho phép (nêu tên, lý do, kích thước, phương án thay thế); không code thừa.
- **Tính năng trọn vẹn**: làm hết vòng đời (tạo, xem, sửa, xoá, trạng thái rỗng, lỗi, quyền, hoàn tác), không để nửa chừng.
- **Giao diện chuẩn, không lỗi**: theo mục 6; không để lỗi hiển thị trên 3 cỡ màn hình, sáng và tối.
- **Kiểm thử cùng PR**: mỗi PR có test cho phần mới. Test giao diện (e2e) dùng dữ liệu riêng, không chờ cứng, phím không phụ thuộc hệ điều hành; test mới chạy lặp 3 lần. **Không nới timeout, không `skip` test, không đẩy commit rỗng để chạy lại CI.** Test chập chờn thì cách ly có hạn (qua sổ cách ly) và báo, không giấu.
- **Tự rà trước khi báo xong**: chạy kiểm kiểu, lint, build thật và test liên quan (<điền: lệnh, ví dụ `scripts/check.sh --quick`); đỏ thì sửa tại chỗ, **không đẩy để xem thử**.
- Kiểm thử lại chỉ phần đã lỗi khi đang sửa; không chạy lại toàn bộ khi không có tệp nào đổi kể từ lần xanh.

## 5. Tên gọi và nhất quán toàn dự án **[LÕI]**

- Chốt **bảng thuật ngữ** một lần ở đầu dự án (Phụ lục A, mục "Thuật ngữ") và dùng thống nhất trong mọi kế hoạch, giao diện, bài hướng dẫn, thông báo lỗi, API. Đổi tên một khái niệm thì đổi ở mọi nơi trong cùng PR.
- Một khái niệm = một tên. Phân biệt rõ các từ dễ nhầm (ví dụ "bản" của sản phẩm khác "phiên bản" của tệp khác "phiên bản phần mềm"); ghi rõ cách gọi đã chốt.
- Dùng thành phần và class **dùng chung** thay vì sửa tay từng chỗ (một nút đóng, một thẻ, một tab dùng cùng một thành phần).
- Giữ nguyên chữ đã được Phuoc chốt (ví dụ tên một màn hình), không tự "cải thiện" từ ngữ.

## 6. Giao diện và thiết kế **[LÕI]**

Phuoc có gu thẩm mỹ cao: **sang, tinh tế, tối giản, hiệu ứng nhẹ mượt, hiện đại, tiện dụng, UX tối ưu.**

### 6.1 Mẫu duyệt trước khi code
- Với **mọi thay đổi giao diện**: làm trước **mẫu trước/sau bằng HTML** (sáng và tối, điện thoại), gửi Phuoc, chờ duyệt, **rồi mới code**. Mẫu lưu ở <điền: thư mục mẫu, ví dụ `plans/` hoặc `design/`>.
- Chụp ảnh mẫu ở 3 cỡ **390 / 820 / 1280 px**, sáng và tối, kèm theo kế hoạch.
- Làm bằng **thành phần dùng chung**; ghi quy tắc chung vào `docs/ui-rules.md` thay vì sửa từng trang.

### 6.2 Phong cách
- Font **Inter** (hoặc <điền: font khác nếu đổi>). Màu chủ đạo <điền: ví dụ gradient xanh #2563eb → #1d4ed8>. **Không dùng quầng tím / gradient hào nhoáng**, không glassmorphism, không icon hoạt hình, không trang trí thừa.
- Thẻ khi rê chuột: viền mảnh màu nhạt của màu chủ đạo. Hàng tab/pill cuộn ngang phải có khoảng đệm dưới, không sát mép.
- Tiêu đề trang cùng một cỡ; header và thanh công cụ hai tầng, **thu gọn khi cuộn**.
- Chữ nhỏ dùng các cỡ 12 / 12.5 / 11 px; không dùng chữ IN HOA nhỏ; không đặt biểu tượng ⓘ đứng riêng (gợi ý gắn liền với nhãn).
- Nút: chữ gọn bên trong nút; chữ bị cắt ba chấm phải có `title` / `aria-label`. Nút phụ ở dạng biểu tượng kèm chú giải.
- Trạng thái chọn: phiến phẳng, bo 12 px, viền focus vẽ vào trong; không để nền chọn tràn mép.

### 6.3 Tối ưu không gian và thói quen đa số người dùng
- Luôn tối ưu không gian, gọn gàng, thuận tiện theo thói quen của đa số người dùng. Trên điện thoại 390 px: không lặp tiêu đề dưới thanh trên cùng, đệm đầu trang nhỏ, gợi ý nằm cùng dòng, nút phụ dạng biểu tượng, **tìm kiếm + bộ lọc + nút chính trên một hàng**.
- **Nút chính dính đáy** trên điện thoại (trong tầm ngón cái).
- **Tìm kiếm không phân biệt dấu tiếng Việt** (gõ "nguyen" tìm ra "Nguyễn").
- **Xoá luôn hỏi xác nhận và nêu tên đối tượng** sắp xoá ("Xoá 'Kế hoạch tháng 12'?"), kèm Hoàn tác khi có thể.
- Trạng thái rỗng có hướng đi tiếp; lỗi không đổ lỗi cho người dùng và có cách khắc phục; nút dùng động từ ("Lưu thay đổi", không dùng "OK"); mọi ô nhập có nhãn hiển thị; ô bắt buộc đánh dấu rõ, ô tuỳ chọn gom vào hàng "Thêm:".
- Hiệu ứng chuyển ngắn, mượt, tôn trọng `prefers-reduced-motion`; điều khiển được bằng bàn phím, có vòng focus rõ.

### 6.4 Kiểm tra bắt buộc
- Mọi màn hình tối ưu cho **390 / 820–1024 / 1280 px**, **sáng và tối**; không tràn ngang trang; vùng chạm đủ lớn cho điện thoại.
- Thiết bị thật Phuoc dùng: <điền: ví dụ Android + Chrome, có dùng VPN>.

## 7. Git, Pull Request và CI **[LÕI]**

- **Làm theo nhánh chủ đề**; mỗi yêu cầu một PR gồm code + test + bài hướng dẫn. Tách PR riêng khi có migration cơ sở dữ liệu, bảo mật, sửa CI, hoặc vượt khoảng 2.500 dòng.
- **Cập nhật nhánh từ main mới nhất** trước khi làm và trước khi mở PR. Sau khi PR đã mở, **không gộp main** nếu GitHub không báo xung đột.
- **Mở PR nháp** ngay sau commit đầu. Gom commit rồi đẩy một lần; không đẩy liên tiếp vài phút. Khi kiểm cục bộ xanh ở commit cuối thì chuyển **Ready for review**.
- **Đã Ready / CI đang chạy thì không đẩy thêm commit.** Góp ý nhỏ của bot ghi vào mô tả PR; chỉ sửa ngay khi CI đỏ hoặc có lỗi nghiêm trọng.
- Đỏ do chập chờn: chạy lại job lỗi thay vì đẩy commit mới (vẫn ghi nhận test chập chờn để sửa). Hai lượt CI đỏ liên tiếp thì dừng và báo Phuoc.
- Mô tả PR theo mẫu `.github/pull_request_template.md` (<điền: nếu có>): kết quả kiểm cục bộ kèm mã commit, bảng đối chiếu từng mục kế hoạch với tệp và test, điểm lệch kế hoạch, cách thử tay.
- **Hàng chờ merge**: tối đa 2 PR Ready cùng lúc và chỉ khi không đụng cùng tệp; merge lần lượt từng PR. Thứ tự ưu tiên: bảo mật / nhánh chính đỏ > sửa lỗi > phụ thuộc > tính năng.
- **Merge**: coordinator tự merge khi PR đã được Phuoc duyệt kế hoạch, CI xanh, không xung đột, không còn điểm cần Phuoc quyết; thread code không tự merge. Báo Phuoc sau khi merge.
- **Mỗi PR không sửa trực tiếp `CHANGELOG.md`, số phiên bản**; thêm một tệp ghi chú thay đổi (<điền: ví dụ `.changes/<chủ-đề>.md` loại `minor`/`patch` + mô tả tiếng Việt) để cơ chế tự gộp đặt phiên bản sau merge. Nếu dự án chưa có cơ chế đó thì số phiên bản và CHANGELOG chỉ chốt ngay trước khi merge.
- Với CI/Runner: không dùng cách làm tốn lượt CI (đóng mở PR, commit rỗng); phần chạy dài đặt đúng chỗ đã thống nhất (<điền: máy cục bộ / CI / đám mây>).

## 8. Phát hành và deploy **[LÕI]**

Mỗi lần thay đổi đều phải:
1. **Backup trước khi deploy** (cơ sở dữ liệu; kèm tệp đính kèm khi đổi lớn). Không đụng trực tiếp cơ sở dữ liệu production.
2. **Cập nhật số phiên bản** hiển thị trong hệ thống và ghi vào **CHANGELOG.md** (theo cơ chế mục 7).
3. **Cập nhật lên GitHub** (commit, PR), rồi **build và deploy lại container** trên máy chủ.
4. **Kiểm tra sau deploy**: container chạy, health, log, và dữ liệu còn nguyên.

Quy tắc an toàn:
- **Chỉ deploy từ nhánh chính sau khi PR đã merge**; mỗi lần một thread; xong và kiểm ổn mới sang việc kế tiếp. **Không deploy từ nhánh của thread.**
- **Deploy chỉ chạy khi Phuoc gõ "Deploy"** trực tiếp trong thread deploy (<điền: thread/kênh deploy>).
- Trước deploy: kiểm xem có người dùng hoặc tác vụ nền đang chạy không (ưu tiên giờ ít người dùng; nếu đông thì báo Phuoc trước); dừng nhẹ nhàng để yêu cầu đang xử lý và tác vụ nền kịp xong; sau deploy kiểm lại dữ liệu, container, health, log.
- Cách deploy / quay lui / backup: <điền: lệnh và đường dẫn trên máy chủ; ví dụ `./scripts/deploy.sh`, `--check`, `--rollback`, `./scripts/backup.sh`>. Không dọn bộ nhớ đệm build của production.
- Thư mục dự án trên máy chủ: <điền: đường dẫn, và xác nhận đã nối Git>.
- Việc đụng migration cơ sở dữ liệu: backup riêng, nêu rõ trong PR, deploy riêng nếu rủi ro.

## 9. Điều phối nhiều thread song song

- **Coordinator** tự đẩy mọi việc đã duyệt đến khi hoàn thành (merge, chuyển bước, mở việc kế tiếp), **không để pending**; chỉ dừng chờ khi cần Phuoc xác nhận hoặc duyệt.
- Mỗi thread một mục tiêu rõ; chuỗi cùng một trang thì làm nối tiếp, không song song; thread xong thì đóng. Thread điều phối CI kiểm định kỳ (<điền: ví dụ 15 phút/lần>); không để CI trống khi còn việc chờ.
- **Thread code chỉ merge theo lệnh coordinator.** Thread gặp test đỏ không thuộc diff của mình ở hai lượt thì báo coordinator kèm tên test và mã lượt chạy, không tự cách ly.
- Mọi brief giao cho thread code phải ghi: đọc tệp hướng dẫn này, dùng bản đồ mã nguồn và chỉ mục đồ thị (mục 10), không đẩy khi CI đang chạy, gom commit, không gộp main khi không xung đột.
- Nhịp: deploy khoảng 2 lần/ngày. Giờ cao điểm của Phuoc ưu tiên việc cần xem bằng trình duyệt; ban đêm ưu tiên việc nặng đã duyệt (<điền: nếu muốn chạy 24/7>). Hết usage thì tự tiếp tục khi có lại.
- Bộ nhớ dự án: mỗi thread lưu lại điều mà thread sau sẽ phải hỏi lại Phuoc.

## 10. Hiểu mã nguồn tiết kiệm usage

- **Bản đồ mã nguồn** (<điền: công cụ, ví dụ `scripts/code-map.mjs`>): trước khi làm, tra theo từ khoá để biết khu nào, đọc trang quy tắc và bẫy của khu; trước khi đổi một thứ dùng chung (thành phần, hàm, bảng, API) chạy lệnh "ai dùng" và xử lý hết nơi dùng. PR thêm / xoá / đổi tên trang, API, bảng, quyền hoặc đổi quy tắc nghiệp vụ thì **sửa trang khu trong chính PR đó**.
- **Chỉ mục đồ thị mã** (<điền: công cụ, ví dụ Graphify>): dùng **trước khi đọc nhiều tệp** (định nghĩa ở đâu, ai gọi, đổi thì ảnh hưởng gì, test liên quan). Kết quả cũ hơn nhánh chính: so mã commit, chỉ đọc phần chênh (diff); kết quả rỗng hoặc thiếu thì đọc tệp trực tiếp. Tệp nào sửa thì vẫn đọc kỹ.
- **Tệp nguy hiểm** (nhiều nơi dùng, đổi sai vỡ lan rộng): bắt buộc chạy phân tích tác động và xử lý hết nơi dùng trước khi sửa. Danh sách: <điền: ví dụ thành phần giao diện gốc, hằng quyền, cấu hình mặc định, điều hướng, danh sách module>.
- Không đọc tràn, không grep rộng khi đã có công cụ chỉ đường.

## 11. Hướng dẫn người dùng và tài liệu

- Có **Trợ giúp trong ứng dụng theo vai** (<điền: đường dẫn bài hướng dẫn>). PR đổi giao diện của một khu phải sửa bài của khu đó trong cùng PR (hoặc ghi rõ "người dùng không thấy thay đổi" ở mô tả PR). Quy tắc viết bài: <điền: `docs/guide-rules.md`>.
- Tài liệu phải ngắn, đúng, cập nhật cùng code. Kế hoạch dài làm thành trang HTML (có ảnh mẫu), bản giao việc cho thread code là tệp Markdown.
- Khi việc kết thúc, nêu rõ điểm lệch so với kế hoạch và cách thử tay.

## 12. Danh sách tự kiểm trước khi báo "xong" **[LÕI]**

- [ ] Đã có xác nhận của Phuoc cho kế hoạch / mẫu giao diện.
- [ ] Đã đối chiếu tiêu chí **mới nhất** của Phuoc, không dùng tiêu chí cũ.
- [ ] Thuật ngữ nhất quán; chữ hiển thị đúng quy ước.
- [ ] Giao diện kiểm ở 390 / 820 / 1280, sáng và tối; không tràn ngang.
- [ ] Kiểm kiểu, lint, build, test liên quan đều xanh; test mới đã chạy lặp 3 lần.
- [ ] Bảo mật: quyền ở máy chủ, không lộ bí mật; đã rà soát bảo mật.
- [ ] Bài hướng dẫn, trang khu (bản đồ mã) và ghi chú thay đổi đã cập nhật trong PR.
- [ ] Có backup, số phiên bản, CHANGELOG; deploy chỉ sau merge và khi Phuoc gõ "Deploy"; đã kiểm container, health, log.
- [ ] Đã nêu 1–3 đề xuất cải tiến liên quan kèm ưu / khuyết / khuyến nghị.
- [ ] Đã ghi điều mới học được vào bộ nhớ dự án.

---

## Phụ lục A. Thông tin riêng của dự án (điền khi khởi tạo)

| Mục | Giá trị |
|---|---|
| Tên dự án, tên hiển thị cho người dùng | <điền> |
| Kho mã (GitHub) và nhánh chính | <điền> |
| Ngăn xếp công nghệ (web, API, cơ sở dữ liệu, hàng đợi, lưu trữ tệp) | <điền> |
| Máy chủ production, đường dẫn thư mục, cách vào | <điền; không ghi mật khẩu> |
| Lệnh kiểm cục bộ trước khi đẩy | <điền> |
| Lệnh deploy / quay lui / backup | <điền> |
| CI: nơi chạy, cách chia phần, sổ cách ly test | <điền> |
| Màu chủ đạo, font, bộ quy tắc giao diện | <điền, ví dụ `docs/ui-rules.md`> |
| Thiết bị Phuoc dùng để thử | <điền> |
| Bản đồ mã nguồn và chỉ mục đồ thị | <điền công cụ và lệnh> |
| Tệp nguy hiểm (cần phân tích tác động) | <điền danh sách> |
| Giờ tổng hợp góp ý hằng ngày | <điền> |
| Nơi lưu kế hoạch, mẫu, hàng đợi góp ý | <điền> |
| Quy ước ghi chú thay đổi / phiên bản | <điền> |

### Thuật ngữ đã chốt
| Khái niệm | Tên dùng thống nhất | Không dùng |
|---|---|---|
| <điền> | <điền> | <điền> |

### Quy tắc nghiệp vụ và bẫy riêng
<điền: gom theo khu, mỗi khu một trang trong `docs/`>

## Phụ lục B. Mẫu khung kế hoạch tính năng (dùng khi xin Phuoc duyệt)

1. Mục tiêu và vấn đề cần giải quyết (một đoạn).
2. Cách hiểu yêu cầu và điểm cần Phuoc quyết (kèm phương án, ưu / khuyết, khuyến nghị).
3. Khu / module bị ảnh hưởng; dữ liệu, API, quyền, migration.
4. Mẫu giao diện: sáng / tối, 390 / 820 / 1280.
5. Bảng đối chiếu ứng dụng tương tự (lấy gì, bỏ gì, làm khác gì).
6. Tự đánh giá theo bốn tiêu chí (mục 2.4), nói thẳng chỗ chưa đạt.
7. Các bước làm, thứ tự PR, test, bài hướng dẫn, rủi ro, cách quay lui.
8. 1–3 đề xuất cải tiến liên quan.
