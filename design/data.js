/*
 * Dữ liệu mẫu dùng chung cho các màn (một nguồn, để Trực tiếp, Soạn thảo và Màn hình nhắc khớp nhau).
 * Lời bài hát "Đấng Chăn Giữ Tôi" do Hệ thống soạn phỏng theo Thi Thiên 23 để làm mẫu, không trích sách Thánh Ca.
 * Câu Kinh Thánh trích Bản Truyền Thống 1925. Số thánh ca là dữ liệu mẫu, chưa đối chiếu sách Thánh Ca.
 */
window.TC_DATA = {
  plan: {
    title: "Chúa Nhật 30/11/2026",
    sub: "Buổi nhóm sáng · bắt đầu 8:50",
    now: "9:12",
    items: [
      { heading: "Trước giờ nhóm" },
      { icon: "photo", title: "Thông báo tuần này", sub: "Ảnh · 4 trang", at: "8:50", dur: "8′" },
      { icon: "film", title: "Đếm ngược vào giờ nhóm", sub: "Video · 2:00", at: "8:58", dur: "2′" },
      { heading: "Thờ phượng" },
      { icon: "note", title: "Lời chào và cầu nguyện mở đầu", sub: "Ghi chú · Mục sư Quản nhiệm", at: "9:00", dur: "3′" },
      { icon: "song", title: "Thánh! Thánh! Thánh!", sub: "Thánh ca 1 · 4 câu", at: "9:03", dur: "4′" },
      { icon: "song", title: "Đấng Chăn Giữ Tôi", sub: "Bài hát · 9 trang", at: "9:07", dur: "5′", live: true, selected: true },
      { icon: "book", title: "Thi Thiên 23:1-6", sub: "Kinh Thánh · Truyền Thống 1925", at: "9:12", dur: "3′", now: true },
      { heading: "Lời Chúa" },
      { icon: "book", title: "Giăng 3:16-18", sub: "Kinh Thánh · Truyền Thống 1925", at: "9:15", dur: "2′" },
      { icon: "theme", title: "Bài giảng: Tình yêu không điều kiện", sub: "Bộ trình chiếu · 18 trang", at: "9:17", dur: "35′" },
      { icon: "song", title: "Bình An Như Dòng Sông", sub: "Thánh ca 47 · 3 câu", at: "9:52", dur: "4′" },
      { icon: "film", title: "Video Trại hè thiếu nhi 2026", sub: "Không tìm thấy", at: "9:56", dur: "2′", missing: true },
      { icon: "note", title: "Dâng hiến", sub: "Ghi chú · Ban Chấp sự", at: "9:58", dur: "3′" },
      { icon: "note", title: "Chúc phước", sub: "Ghi chú", at: "10:01", dur: "1′" },
    ],
  },
  song: {
    title: "Đấng Chăn Giữ Tôi",
    meta: "Phỏng theo Thi Thiên 23 · Bài mẫu",
    groups: {
      v1: { label: "Câu 1", c: "var(--g-verse)", slides: ["Ngài là Đấng chăn giữ tôi\nTôi chẳng thiếu thốn gì", "Đồng cỏ xanh, dòng nước êm\nLinh hồn tôi được yên"] },
      ch: { label: "Điệp khúc", c: "var(--g-chorus)", slides: ["Dù qua trũng bóng tối tăm\nTôi chẳng sợ điều chi", "Vì Chúa luôn ở cùng tôi\nCây gậy Ngài an ủi"] },
      v2: { label: "Câu 2", c: "var(--g-verse)", slides: ["Ngài dọn bàn trước mặt tôi\nXức dầu cho đầu tôi", "Chén tôi đầy tràn phước ân\nƠn thương xót theo tôi"] },
      end: { label: "Kết", c: "var(--g-ending)", slides: ["Trọn đời tôi sẽ ở trong\nNhà Chúa đến đời đời"] },
    },
    arrangement: ["v1", "ch", "v2", "ch", "end"],
    notes: { 2: "Lần 1: cả ban nhạc vào", 6: "Lần 2: hát nhỏ, chỉ đàn piano" },
  },
  // Trang chiếu theo thứ tự hát
  slides() {
    const s = this.song, out = [];
    s.arrangement.forEach((g) => s.groups[g].slides.forEach((t, i) => out.push({ g, label: s.groups[g].label, c: s.groups[g].c, text: t, idx: i })));
    return out;
  },
  scripture: {
    ref: "Giăng 3",
    translation: "Truyền Thống 1925",
    verses: [
      [14, "Xưa Môi-se treo con rắn lên nơi đồng vắng thể nào, thì Con người cũng phải bị treo lên dường ấy,"],
      [15, "hầu cho hễ ai tin đến Ngài đều được sự sống đời đời."],
      [16, "Vì Đức Chúa Trời yêu thương thế gian, đến nỗi đã ban Con một của Ngài, hầu cho hễ ai tin Con ấy không bị hư mất mà được sự sống đời đời."],
      [17, "Vả, Đức Chúa Trời đã sai Con Ngài xuống thế gian, chẳng phải để đoán xét thế gian đâu, nhưng hầu cho thế gian nhờ Con ấy mà được cứu."],
      [18, "Ai tin Con ấy thì chẳng bị đoán xét đâu; ai không tin thì đã bị đoán xét rồi, vì không tin đến danh Con một Đức Chúa Trời."],
    ],
  },
  songs: [
    { title: "Thánh! Thánh! Thánh!", no: 1, author: "Reginald Heber", tags: ["Ngợi khen"], edited: "28/11/2026" },
    { title: "Lớn Bấy Duy Ngài", no: 15, author: "Carl Boberg", tags: ["Ngợi khen", "Thờ phượng"], edited: "21/11/2026" },
    { title: "Đấng Chăn Giữ Tôi", no: null, author: "Phỏng theo Thi Thiên 23", tags: ["Thờ phượng"], edited: "Hôm nay, 8:41" },
    { title: "Ân Điển Lạ Lùng", no: 302, author: "John Newton", tags: ["Thờ phượng", "Làm chứng"], edited: "14/11/2026" },
    { title: "Bình An Như Dòng Sông", no: 47, author: "Horatio G. Spafford", tags: ["An ủi"], edited: "09/11/2026" },
    { title: "Vầng Đá Muôn Đời", no: 205, author: "Augustus Toplady", tags: ["Thờ phượng"], edited: "02/11/2026" },
    { title: "Đứng Trên Lời Hứa", no: 361, author: "R. Kelso Carter", tags: ["Đức tin"], edited: "26/10/2026" },
    { title: "Cây Thập Tự Xưa", no: 120, author: "George Bennard", tags: ["Tiệc Thánh"], edited: "19/10/2026" },
    { title: "Ngày Vui Vẻ", no: 244, author: "Philip Doddridge", tags: ["Báp-têm"], edited: "05/10/2026" },
    { title: "Chúa Giê-xu Yêu Tôi", no: 411, author: "Anna B. Warner", tags: ["Thiếu nhi"], edited: "28/09/2026" },
    { title: "Đêm Thánh Vô Cùng", no: 86, author: "Joseph Mohr", tags: ["Giáng Sinh"], edited: "24/12/2025" },
    { title: "Tôn Vinh Chúa Giê-xu", no: null, author: "Ban Thờ phượng", tags: ["Ngợi khen", "Thanh niên"], edited: "16/11/2026" },
    { title: "Hội Thánh Hiệp Một", no: null, author: "Ban Thờ phượng", tags: ["Thờ phượng"], edited: "07/11/2026" },
    { title: "Lời Chúa Là Đèn", no: 173, author: "Bài mẫu", tags: ["Lời Chúa"], edited: "31/10/2026" },
  ],
};
