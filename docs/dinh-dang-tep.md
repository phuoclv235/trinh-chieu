# Định dạng tệp và thư mục thư viện (schemaVersion 1)

Tệp nguy hiểm về mặt dữ liệu người dùng. Mọi thay đổi phải tăng `schemaVersion`, có migration tự động, giữ bản `.bak` của tệp cũ, và có test đọc tệp mẫu của phiên bản trước (`Tests/Fixtures/schema-v<N>/`).

## 1. Thư mục thư viện

Mặc định `~/Documents/TrinhChieu/` (đổi được trong Cài đặt). Người dùng có thể đặt trong iCloud Drive hoặc Dropbox; mọi tên tệp chỉ dùng ASCII để tránh lỗi chuẩn hoá Unicode giữa các hệ đồng bộ.

```
TrinhChieu/
  library.json                 Thông tin thư viện: id, schemaVersion, ngày tạo
  presentations/<uuid>.json    Mỗi bộ trình chiếu một tệp
  themes/<uuid>.json           Mỗi mẫu trình bày một tệp
  plans/<uuid>.json            Mỗi chương trình buổi nhóm một tệp
  media/<sha256-12>.<ext>      Media, đặt tên theo 12 ký tự đầu của SHA-256 nội dung
  media/<sha256-12>.json       Thông tin media: tên gốc, kích thước, thời lượng, thẻ
  bibles/<code>.sqlite         Mỗi bản dịch Kinh Thánh một tệp, xem mục 5
  logs/<yyyy-mm-dd>-<uuid>.json Nhật ký buổi nhóm
  .cache/index.sqlite          Chỉ mục tìm kiếm; xoá được, tự dựng lại
  .cache/thumbs/               Ảnh thu nhỏ; xoá được
  .trash/                      Tệp đã xoá, giữ 30 ngày để hoàn tác
```

Quy tắc ghi:

- Ghi nguyên tử: ghi `<tên>.json.tmp` rồi đổi tên. Không bao giờ ghi đè trực tiếp.
- JSON mã hoá với `.prettyPrinted, .sortedKeys`, ngày giờ ISO 8601 UTC, để diff được và đồng bộ ít xung đột.
- Xoá = chuyển vào `.trash/` kèm thời điểm xoá trong tên. Dọn sau 30 ngày khi mở ứng dụng.
- Media trùng nội dung chỉ lưu một bản (theo SHA-256).
- **Media liên kết** (NAS, Phuoc yêu cầu 2026-11-26): không có tệp trong `media/`, chỉ có `media/<id>.json` với `"origin": {"kind": "linked", "url": "https://..."}`; `id` là `l-` + 10 ký tự hex đầu của SHA-256 của URL. Bản tải về nằm ở `.cache/media/<id>.<ext>`, xoá được. Media chép vào thư viện có `"origin": {"kind": "copied"}`. Trường `origin` có từ schemaVersion 1 (giai đoạn 1 chỉ cần đọc ghi trường này; chức năng liên kết làm ở giai đoạn 2b).

## 2. `Presentation` (bộ trình chiếu)

```json
{
  "schemaVersion": 1,
  "id": "UUID",
  "kind": "song | generic",
  "title": "Chúa Là Đá Muôn Đời",
  "createdAt": "2026-11-26T10:00:00Z",
  "modifiedAt": "2026-11-26T10:00:00Z",
  "tags": ["thánh ca"],
  "themeID": "UUID hoặc null (null = mẫu mặc định của thư viện)",
  "song": {
    "number": "123",
    "hymnal": "Thánh Ca",
    "authors": ["..."],
    "copyright": "...",
    "ccli": null,
    "key": "G",
    "tempo": null
  },
  "groups": [
    {
      "id": "UUID",
      "label": { "kind": "verse | chorus | prechorus | bridge | tag | intro | ending | custom", "number": 1, "custom": null },
      "color": null,
      "slides": [ { "...Slide..." } ]
    }
  ],
  "arrangements": [ { "id": "UUID", "name": "Mặc định", "groupIDs": ["UUID", "UUID"] } ],
  "activeArrangementID": "UUID hoặc null (null = thứ tự các đoạn như trong groups)"
}
```

`song` là `null` khi `kind` là `generic`. Một đoạn có thể xuất hiện nhiều lần trong `groupIDs`.

### `Slide`

```json
{
  "id": "UUID",
  "label": null,
  "enabled": true,
  "notes": "Ghi chú cho màn hình nhắc",
  "background": { "kind": "none | color | media", "color": "#000000FF", "mediaID": "sha256-12", "loop": true, "muted": false },
  "elements": [ { "...Element..." } ]
}
```

`background.kind = none` nghĩa là dùng nền của mẫu trình bày. Khi lên màn, trang chỉ thay lớp nền nếu nó có nền riêng.

### `Element`

Toạ độ tính bằng điểm ảnh trong khung vẽ của mẫu (`Theme.canvasSize`), gốc ở góc trên trái.

```json
{ "id": "UUID", "type": "text",  "frame": [x, y, w, h], "slot": "body | title | reference | null", "text": "Dòng 1\nDòng 2", "style": { "...TextStyle, chỉ các trường muốn đè..." } }
{ "id": "UUID", "type": "image", "frame": [x, y, w, h], "mediaID": "sha256-12", "fit": "fit | fill | stretch", "opacity": 1.0 }
{ "id": "UUID", "type": "video", "frame": [x, y, w, h], "mediaID": "sha256-12", "fit": "fit | fill | stretch", "loop": false, "muted": false }
{ "id": "UUID", "type": "shape", "frame": [x, y, w, h], "shape": "rect", "fill": "#00000080", "cornerRadius": 0 }
```

Phần tử chữ có `slot` khác `null` thì lấy khung và kiểu từ ô mẫu tương ứng của mẫu trình bày; `frame` khi đó bị bỏ qua, `style` chỉ đè các trường được ghi. Đây là cách đổi mẫu trình bày mà không sửa từng trang.

### `TextStyle`

```json
{
  "fontFamily": "system",
  "fontWeight": 600,
  "fontSize": 72,
  "color": "#FFFFFFFF",
  "alignment": "left | center | right | justified",
  "verticalAlignment": "top | middle | bottom",
  "lineHeight": 1.2,
  "letterSpacing": 0,
  "transform": "none | uppercase",
  "stroke": { "color": "#000000FF", "width": 0 },
  "shadow": { "color": "#00000099", "radius": 8, "offset": [0, 4] },
  "box": { "color": "#00000000", "padding": [0, 0, 0, 0], "cornerRadius": 0 },
  "autoFit": { "mode": "none | shrink", "minScale": 0.5 },
  "maxLines": null
}
```

Màu viết dạng `#RRGGBBAA`. `fontFamily = "system"` nghĩa là phông hệ thống của macOS (San Francisco); tên khác là tên họ phông đã cài trên máy. Phông không có trên máy thì dùng phông hệ thống và hiện cảnh báo trên màn điều khiển (không hiện trên đầu ra).

## 3. `Theme` (mẫu trình bày)

```json
{
  "schemaVersion": 1,
  "id": "UUID",
  "name": "Lời bài hát giữa màn",
  "canvasSize": [1920, 1080],
  "background": { "kind": "color | media", "color": "#000000FF", "mediaID": null, "loop": true },
  "slots": {
    "body":      { "frame": [120, 140, 1680, 800], "style": { "...TextStyle đầy đủ..." } },
    "title":     { "frame": [120, 60, 1680, 80],   "style": { "..." } },
    "reference": { "frame": [120, 960, 1680, 60],  "style": { "..." } }
  },
  "lyrics": { "maxLinesPerSlide": 4 },
  "scripture": { "maxCharactersPerSlide": 220, "showReference": true, "referencePosition": "bottom | top", "verseNumbers": "superscript | none" },
  "transition": { "kind": "cut | dissolve", "duration": 0.35 }
}
```

Thư viện mới tạo có sẵn 3 mẫu: "Lời bài hát giữa màn", "Lời bài hát dưới màn" (cho camera và Zoom), "Kinh Thánh". Mẫu mặc định của thư viện lưu trong `library.json` (`defaultThemeID`, `defaultScriptureThemeID`).

## 4. `ServicePlan` (chương trình buổi nhóm)

```json
{
  "schemaVersion": 1,
  "id": "UUID",
  "title": "Chúa Nhật 30/11/2026",
  "date": "2026-11-30",
  "plannedStart": "09:00",
  "items": [
    { "id": "UUID", "type": "header", "title": "Thờ phượng", "plannedDuration": null },
    { "id": "UUID", "type": "presentation", "presentationID": "UUID", "arrangementID": null, "themeID": null, "plannedDuration": 300 },
    { "id": "UUID", "type": "scripture", "reference": "Giăng 3:16-18", "translation": "vi1925", "themeID": null, "plannedDuration": 120 },
    { "id": "UUID", "type": "media", "mediaID": "sha256-12", "plannedDuration": null },
    { "id": "UUID", "type": "note", "text": "Mời Hội Thánh đứng", "plannedDuration": null }
  ]
}
```

`plannedDuration` tính bằng giây. `themeID` ở mục đè mẫu của bộ trình chiếu chỉ trong chương trình này.

## 5. Bản dịch Kinh Thánh (`bibles/<code>.sqlite`)

Nhập từ OSIS, USFM hoặc Zefania một lần, sau đó chỉ đọc.

```sql
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- key: code, name, language, source, license, importedAt, schemaVersion
CREATE TABLE verses(
  book TEXT NOT NULL,        -- mã sách OSIS: Gen, Exod, ..., John, ..., Rev
  chapter INTEGER NOT NULL,
  verse INTEGER NOT NULL,
  text TEXT NOT NULL,        -- NFC, đã bỏ chú thích và thẻ
  PRIMARY KEY(book, chapter, verse)
) WITHOUT ROWID;
CREATE TABLE books(osis TEXT PRIMARY KEY, ordinal INTEGER NOT NULL, name TEXT NOT NULL, chapters INTEGER NOT NULL);
```

Tìm kiếm nội dung câu nằm ở chỉ mục chung (`.cache/index.sqlite`), không nằm trong tệp bản dịch.

## 6. Chỉ mục tìm kiếm (`.cache/index.sqlite`)

Dựng lại hoàn toàn từ các tệp được. Khi `indexVersion` trong bảng `meta` khác hằng số trong code, xoá và dựng lại.

```sql
CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE items(
  id TEXT PRIMARY KEY,           -- UUID, mã media, hoặc "bible:<code>:<book>.<c>.<v>"
  kind TEXT NOT NULL,            -- presentation | theme | plan | media | verse
  title TEXT NOT NULL,
  subtitle TEXT,                 -- số thánh ca, tác giả, địa chỉ câu
  path TEXT,
  modifiedAt TEXT
);
CREATE VIRTUAL TABLE items_fts USING fts5(
  id UNINDEXED, kind UNINDEXED,
  title_f, subtitle_f, body_f,   -- đã gộp dấu bằng VietText.fold
  tokenize = 'unicode61'
);
```

Truy vấn: chuỗi người dùng gõ cũng gộp dấu, mỗi từ thêm `*` để khớp tiền tố. Xếp hạng `bm25(items_fts, 10.0, 5.0, 1.0)`.

## 7. Gói mang đi (`.tcbundle`)

Tệp ZIP chứa `manifest.json` (loại: `plan` hoặc `presentation`, `schemaVersion`, danh sách tệp), cùng các tệp JSON và media liên quan theo đúng cấu trúc thư mục ở mục 1. Mở gói: chép vào thư viện, bỏ qua media đã có (cùng SHA-256), hỏi khi trùng `id` mà nội dung khác ("Giữ cả hai", "Thay bản trong thư viện", "Bỏ qua").

## 8. Nhật ký buổi nhóm (`logs/*.json`)

```json
{ "schemaVersion": 1, "planID": "UUID hoặc null", "startedAt": "...", "events": [
  { "at": "2026-11-30T09:01:12.120Z", "type": "goLive", "itemID": "UUID", "presentationID": "UUID", "slideID": "UUID" },
  { "at": "...", "type": "clearLayer", "layer": "slide" }
] }
```

Ghi theo lô mỗi 5 giây và khi đóng ứng dụng. Giai đoạn 1 chỉ ghi, chưa có màn xem lại.
