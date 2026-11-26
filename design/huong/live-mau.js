/*
 * Dựng màn Trực tiếp ở mức căn bản, dùng chung cho 3 hướng thẩm mỹ.
 * Cấu trúc giống hệt nhau; mỗi hướng chỉ khác tệp CSS, để so sánh công bằng.
 */
(function () {
  const D = window.TC_DATA;
  const ic = (n) => `<svg class="ic" aria-hidden="true"><use href="#i-${n}"/></svg>`;
  const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
  const LIVE = 2, NEXT = 3;

  const plan = D.plan.items.map((it) => {
    if (it.heading) return `<li class="p-head">${it.heading}</li>`;
    const cls = ["p-row", it.live && "is-live", it.selected && "is-sel", it.missing && "is-missing"].filter(Boolean).join(" ");
    const nowLine = it.now ? `<li class="p-now" aria-label="Bây giờ 9:12"><span>9:12</span></li>` : "";
    return nowLine + `<li class="${cls}"><span class="p-at">${it.at}</span><span class="p-ic">${ic(it.icon)}</span>` +
      `<span class="p-main"><span class="p-title">${esc(it.title)}</span><span class="p-sub">${esc(it.sub)}</span></span>` +
      `<span class="p-dur">${it.live ? '<i class="tally"></i>' : ""}${it.dur}</span></li>`;
  }).join("");

  const songs = D.songs.slice(0, 7).map((s, i) =>
    `<li class="l-row${i === 2 ? " is-sel" : ""}"><span class="l-no">${s.no ?? "–"}</span><span class="l-title">${esc(s.title)}</span><span class="l-meta">${esc(s.author)}</span></li>`).join("");

  const slides = D.slides();
  const cards = slides.map((s, i) => {
    const st = i === LIVE ? "is-live" : i === NEXT ? "is-next" : "";
    const tag = i === LIVE ? '<span class="c-tag">Trên màn</span>' : i === NEXT ? '<span class="c-tag c-tag--next">Kế tiếp</span>' : "";
    return `<button class="card ${st}" style="--c:${s.c}"><span class="c-frame"><span class="c-text">${esc(s.text).replace("\n", "<br>")}</span>${tag}</span>` +
      `<span class="c-cap"><span class="c-num">${String(i + 1).padStart(2, "0")}</span><span class="c-label">${s.label}</span></span></button>`;
  }).join("");

  const arr = D.song.arrangement.map((g, i) => `<span class="chip${i === 1 ? " is-cur" : ""}" style="--c:${D.song.groups[g].c}">${D.song.groups[g].label}</span>`).join("");
  const cur = slides[LIVE], nxt = slides[NEXT];

  document.getElementById("app").innerHTML = `
  <header class="tb">
    <div class="traffic"><span></span><span></span><span></span></div>
    <div class="seg"><button class="is-on">Trực tiếp</button><button>Soạn thảo</button></div>
    <div class="tb-search">${ic("search")}<span>Tìm bài hát, câu Kinh Thánh, lệnh…</span><kbd>⌘K</kbd></div>
    <div class="tb-right">
      <span class="fps"><i></i>60 khung/giây</span>
      <button class="tgl tgl--reh">${ic("rehearsal")}Tập dượt<kbd>⌘R</kbd></button>
      <button class="tgl tgl--frz">${ic("snowflake")}Đóng băng<kbd>⌘⇧F</kbd></button>
    </div>
  </header>
  <div class="cols">
    <aside class="left">
      <section class="plan">
        <div class="sec-head"><div><h2>${D.plan.title}</h2><p>${D.plan.sub}</p></div><button class="ib" title="Thêm mục">${ic("plus")}</button></div>
        <ol class="p-list">${plan}</ol>
      </section>
      <section class="lib">
        <nav class="tabs"><button class="is-on">Bài hát</button><button>Kinh Thánh</button><button>Media</button><button>Mẫu</button></nav>
        <div class="l-search">${ic("search")}<span>Tìm không cần dấu</span></div>
        <ul class="l-list">${songs}</ul>
      </section>
    </aside>
    <main class="center">
      <div class="c-head">
        <div class="c-titles"><h1>${D.song.title}</h1><p>${D.song.meta}</p></div>
        <div class="c-tools"><span class="c-arrlabel">Thứ tự hát</span>${arr}<button class="ib" title="Soạn bộ trình chiếu này">${ic("pencil")}</button></div>
      </div>
      <div class="grid">${cards}</div>
    </main>
    <aside class="right">
      <div class="pv"><div class="pv-head"><i class="tally"></i><b>Đầu ra chính</b><span>Bộ xử lý LED · HDMI</span></div>
        <div class="pv-frame"><span class="c-text">${esc(cur.text).replace("\n", "<br>")}</span></div></div>
      <div class="pv"><div class="pv-head"><i class="tally tally--idle"></i><b>Màn hình nhắc</b><span>Màn bục giảng</span></div>
        <div class="pv-frame pv-stage"><span class="st-top"><span>${D.song.title} · ${cur.label}</span><span>09:12:48</span></span>
          <span class="st-cur">${esc(cur.text).replace("\n", "<br>")}</span><span class="st-next">${esc(nxt.text).replace("\n", "<br>")}</span>
          <span class="st-note">Lần 1: cả ban nhạc vào</span></div></div>
      <div class="layers">
        <div class="r-label">Xoá lớp</div>
        <div class="lay-grid">
          <button class="lay is-active"><b>Chữ</b><kbd>F2</kbd></button>
          <button class="lay is-active"><b>Nền</b><kbd>F3</kbd></button>
          <button class="lay"><b>Âm thanh</b><kbd>F4</kbd></button>
        </div>
        <button class="clear-all">Xoá tất cả<kbd>F1</kbd></button>
      </div>
      <div class="clock">
        <div class="r-label">Giờ thật</div>
        <div class="ck-time">9:12:48</div>
        <div class="ck-row"><span>Mục này bắt đầu</span><b>9:10</b></div>
        <div class="ck-row"><span>So với dự kiến 9:07</span><b class="late">Trễ 3 phút</b></div>
        <div class="ck-row"><span>Kết thúc dự kiến</span><b>10:05</b></div>
      </div>
    </aside>
  </div>
  <div class="dock" role="toolbar" aria-label="Điều khiển nhanh">
    <span class="dk-count">Trang 03 / 09</span>
    <button class="dk-btn is-active">Chữ<kbd>F2</kbd></button>
    <button class="dk-btn is-active">Nền<kbd>F3</kbd></button>
    <button class="dk-btn">Âm thanh<kbd>F4</kbd></button>
    <button class="dk-btn dk-all">Xoá tất cả<kbd>F1</kbd></button>
  </div>`;
})();
