/*
 * TrinhChieu · Mã dùng chung cho mẫu giao diện
 * 1. Đọc lựa chọn hiển thị (sáng tối, phông A/B) từ địa chỉ hoặc lần xem trước.
 * 2. Chèn bộ biểu tượng SVG nét mảnh (mô phỏng SF Symbols; bản thật dùng SF Symbols).
 * 3. Dựng thanh duyệt mẫu ở góc dưới trái (không thuộc ứng dụng; ẩn khi chụp ảnh với ?shot).
 */
(function () {
  const root = document.documentElement;
  const params = new URLSearchParams(location.search);
  const store = {
    get(k) { try { return localStorage.getItem("tc-mau-" + k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem("tc-mau-" + k, v); } catch (e) { /* trình duyệt chặn lưu trữ: bỏ qua */ } },
  };
  const defaults = { theme: "dark", font: "a" };
  for (const k of Object.keys(defaults)) {
    const v = params.get(k) || store.get(k) || defaults[k];
    root.setAttribute("data-" + k, v);
  }
  if (params.has("shot")) root.setAttribute("data-shot", "");
  if (params.get("state")) root.setAttribute("data-state", params.get("state"));

  const ICONS = {
    search: '<circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5 14 14"/>',
    sidebar: '<rect x="1.75" y="2.75" width="12.5" height="10.5" rx="2"/><path d="M10 2.75v10.5"/>',
    snowflake: '<path d="M8 1.5v13M2.4 4.75l11.2 6.5M2.4 11.25l11.2-6.5M6.4 2.6 8 4.2l1.6-1.6M6.4 13.4 8 11.8l1.6 1.6"/>',
    rehearsal: '<circle cx="8" cy="8" r="6.25" stroke-dasharray="2.2 2.1"/><path d="M6.75 5.6v4.8L10.6 8z"/>',
    song: '<path d="M6 12.5V3.6l7-1.6v8.8"/><circle cx="4.25" cy="12.5" r="1.75"/><circle cx="11.25" cy="10.8" r="1.75"/>',
    book: '<path d="M8 4.1C6.5 2.9 4.5 2.6 2 2.9v9.6c2.5-.3 4.5 0 6 1.2 1.5-1.2 3.5-1.5 6-1.2V2.9c-2.5-.3-4.5 0-6 1.2zM8 4.1v9.6"/>',
    photo: '<rect x="1.75" y="2.75" width="12.5" height="10.5" rx="2"/><circle cx="5.5" cy="6.25" r="1.25"/><path d="m2 11.5 3.5-3 3 2.5 2-1.5 3.5 2.75"/>',
    film: '<rect x="1.75" y="2.75" width="12.5" height="10.5" rx="2"/><path d="M5 2.75v10.5M11 2.75v10.5M1.75 8H5M11 8h3.25"/>',
    note: '<path d="M2.5 3.5h11M2.5 6.5h8M2.5 9.5h11M2.5 12.5h6"/>',
    theme: '<rect x="4.5" y="4.5" width="9.5" height="9.5" rx="1.5"/><path d="M2 11V3.5A1.5 1.5 0 0 1 3.5 2H11"/>',
    plus: '<path d="M8 3v10M3 8h10"/>',
    trash: '<path d="M2.75 4.5h10.5M6.25 4.5V2.75h3.5V4.5M4.25 4.5l.6 8.4a1.25 1.25 0 0 0 1.25 1.1h3.8a1.25 1.25 0 0 0 1.25-1.1l.6-8.4"/>',
    undo: '<path d="M5.5 3.5 2.5 6.5l3 3M2.5 6.5h7a3.75 3.75 0 0 1 0 7.5H7"/>',
    redo: '<path d="M10.5 3.5l3 3-3 3M13.5 6.5h-7a3.75 3.75 0 0 0 0 7.5H9"/>',
    sliders: '<path d="M2.5 5h6M11.5 5h2M2.5 11h2M7.5 11h6"/><circle cx="10" cy="5" r="1.5"/><circle cx="6" cy="11" r="1.5"/>',
    display: '<rect x="1.75" y="2.5" width="12.5" height="8.5" rx="1.5"/><path d="M6 13.75h4M8 11v2.75"/>',
    speaker: '<path d="M2.5 6v4H5l3.5 3V3L5 6z"/><path d="M11 5.5a3.5 3.5 0 0 1 0 5M12.8 3.8a6 6 0 0 1 0 8.4"/>',
    folder: '<path d="M1.75 4.5A1.5 1.5 0 0 1 3.25 3h3l1.5 1.5h5a1.5 1.5 0 0 1 1.5 1.5v5.5a1.5 1.5 0 0 1-1.5 1.5h-9.5a1.5 1.5 0 0 1-1.5-1.5z"/>',
    "chevron-down": '<path d="m4 6 4 4 4-4"/>',
    "chevron-right": '<path d="m6 4 4 4-4 4"/>',
    "chevron-left": '<path d="m10 4-4 4 4 4"/>',
    grip: '<path d="M6 4h.01M10 4h.01M6 8h.01M10 8h.01M6 12h.01M10 12h.01" stroke-width="2.2"/>',
    text: '<path d="M3 3.5h10M8 3.5V13M6 13h4"/>',
    shape: '<rect x="2.5" y="2.5" width="11" height="11" rx="1.5"/>',
    "align-left": '<path d="M2.5 3.5h11M2.5 6.5h7M2.5 9.5h11M2.5 12.5h7"/>',
    "align-center": '<path d="M2.5 3.5h11M4.5 6.5h7M2.5 9.5h11M4.5 12.5h7"/>',
    "align-right": '<path d="M2.5 3.5h11M6.5 6.5h7M2.5 9.5h11M6.5 12.5h7"/>',
    "valign-top": '<path d="M2.5 2.5h11M5.5 5.5h5v5h-5z"/>',
    "valign-middle": '<path d="M2.5 8h3M10.5 8h3M5.5 5h5v6h-5z"/>',
    "valign-bottom": '<path d="M2.5 13.5h11M5.5 5.5h5v5h-5z"/>',
    eye: '<path d="M1.5 8S4 3.5 8 3.5 14.5 8 14.5 8 12 12.5 8 12.5 1.5 8 1.5 8z"/><circle cx="8" cy="8" r="2"/>',
    lock: '<rect x="3" y="7" width="10" height="7" rx="1.5"/><path d="M5 7V5a3 3 0 0 1 6 0v2"/>',
    calendar: '<rect x="2" y="3" width="12" height="11" rx="1.5"/><path d="M2 6.5h12M5.5 1.5v3M10.5 1.5v3"/>',
    clock: '<circle cx="8" cy="8" r="6.25"/><path d="M8 4.5V8l2.5 1.5"/>',
    ellipsis: '<path d="M3.5 8h.01M8 8h.01M12.5 8h.01" stroke-width="2.2"/>',
    x: '<path d="m4 4 8 8M12 4l-8 8"/>',
    check: '<path d="m3 8.5 3 3 7-7"/>',
    import: '<path d="M8 2v8M5 7l3 3 3-3M2.5 10.5v2A1.5 1.5 0 0 0 4 14h8a1.5 1.5 0 0 0 1.5-1.5v-2"/>',
    tag: '<path d="M2 2.75v4.6c0 .4.16.78.44 1.06l5.6 5.6a1.25 1.25 0 0 0 1.77 0l4.1-4.1a1.25 1.25 0 0 0 0-1.77l-5.6-5.6A1.5 1.5 0 0 0 7.25 2.1H2.75z"/><circle cx="5.25" cy="5.5" r="1"/>',
    pencil: '<path d="m10.5 2.5 3 3L6 13H3v-3zM9 4l3 3"/>',
    grid: '<rect x="2" y="2" width="5" height="5" rx="1"/><rect x="9" y="2" width="5" height="5" rx="1"/><rect x="2" y="9" width="5" height="5" rx="1"/><rect x="9" y="9" width="5" height="5" rx="1"/>',
    live: '<circle cx="8" cy="8" r="1.5"/><path d="M5.2 10.8a4 4 0 0 1 0-5.6M10.8 5.2a4 4 0 0 1 0 5.6M3.1 12.9a7 7 0 0 1 0-9.8M12.9 3.1a7 7 0 0 1 0 9.8"/>',
    warning: '<path d="M8 2.25 14.5 13.5h-13zM8 6.5v3.25M8 11.75h.01"/>',
    number: '<path d="M6 2.5 5 13.5M11 2.5l-1 11M2.75 6h11M2.25 10h11"/>',
    person: '<circle cx="8" cy="5.25" r="2.75"/><path d="M2.75 14c.8-2.8 2.9-4.25 5.25-4.25S12.45 11.2 13.25 14"/>',
    list: '<path d="M5.5 4h8M5.5 8h8M5.5 12h8M2.5 4h.01M2.5 8h.01M2.5 12h.01"/>',
    sort: '<path d="M5 3v10M2.5 5.5 5 3l2.5 2.5M11 13V3M8.5 10.5 11 13l2.5-2.5"/>',
    filter: '<path d="M2 3.5h12l-4.75 5.5v4L6.75 14.5V9z"/>',
    play: '<path d="M5 3.5v9l7.5-4.5z"/>',
    loop: '<path d="M3 7v-.5A2.5 2.5 0 0 1 5.5 4h7M10.5 2l2 2-2 2M13 9v.5A2.5 2.5 0 0 1 10.5 12h-7M5.5 14l-2-2 2-2"/>',
    layers: '<path d="M8 2 14 5 8 8 2 5zM2 8l6 3 6-3M2 11l6 3 6-3"/>',
    gauge: '<path d="M2.5 11.5a5.5 5.5 0 1 1 11 0M8 11.5l2.5-3.5"/>',
    hymnal: '<rect x="3" y="1.75" width="10" height="12.5" rx="1.25"/><path d="M8 4.5v4M6 6.25h4"/>',
    split: '<path d="M2.5 8h11M8 2.5v3M8 10.5v3"/>',
    bring: '<rect x="5.5" y="5.5" width="8" height="8" rx="1.25"/><path d="M2.5 10.5v-7a1 1 0 0 1 1-1h7"/>',
  };
  const sprite = '<svg xmlns="http://www.w3.org/2000/svg" style="display:none" aria-hidden="true">' +
    Object.entries(ICONS).map(([k, v]) => `<symbol id="i-${k}" viewBox="0 0 16 16">${v}</symbol>`).join("") + "</svg>";

  function ready(fn) { document.readyState === "loading" ? document.addEventListener("DOMContentLoaded", fn) : fn(); }

  ready(function () {
    document.body.insertAdjacentHTML("afterbegin", sprite);
    buildMockbar();
  });

  const PAGES = window.MOCK_PAGES || [
    ["components.html", "Thành phần"],
    ["live.html", "Trực tiếp"],
    ["editor.html", "Soạn thảo"],
    ["library.html", "Thư viện"],
    ["settings-outputs.html", "Cài đặt đầu ra"],
    ["stage.html", "Màn hình nhắc"],
  ];

  function buildMockbar() {
    const here = location.pathname.split("/").pop() || "index.html";
    const bar = document.createElement("nav");
    bar.className = "mockbar";
    bar.setAttribute("aria-label", "Thanh duyệt mẫu");
    bar.dataset.collapsed = store.get("bar") === "min" ? "true" : "false";
    const link = ([href, label]) => `<a href="${href}" class="${href === here ? "is-current" : ""}">${label}</a>`;
    const toggle = (k, a, b, la, lb) => `<button type="button" data-k="${k}" data-v="${a}">${la}</button><button type="button" data-k="${k}" data-v="${b}">${lb}</button>`;
    const states = (window.MOCK_STATES || []).map(([v, l]) => `<button type="button" data-k="state" data-v="${v}">${l}</button>`).join("");
    bar.innerHTML =
      `<button type="button" class="mockbar__toggle" title="Thu gọn hoặc mở thanh duyệt mẫu">Mẫu T0.3</button>` +
      `<span class="mockbar__sep"></span>` + PAGES.map(link).join("") +
      `<span class="mockbar__sep"></span>` + toggle("theme", "dark", "light", "Tối", "Sáng") +
      (window.MOCK_PAGES ? "" : `<span class="mockbar__sep"></span><span class="mockbar__tag">Phông</span>` + toggle("font", "a", "b", "A", "B") +
      "") +
      (states ? `<span class="mockbar__sep"></span><span class="mockbar__tag">Trạng thái</span>${states}` : "");
    document.body.appendChild(bar);
    const sync = () => bar.querySelectorAll("button[data-k]").forEach((btn) => {
      const cur = root.getAttribute("data-" + btn.dataset.k) || "";
      btn.classList.toggle("is-current", cur === btn.dataset.v);
    });
    bar.addEventListener("click", (e) => {
      const btn = e.target.closest("button");
      if (!btn) return;
      if (btn.classList.contains("mockbar__toggle")) {
        const min = bar.dataset.collapsed !== "true";
        bar.dataset.collapsed = String(min);
        store.set("bar", min ? "min" : "max");
        return;
      }
      const k = btn.dataset.k, v = btn.dataset.v;
      if (k === "state") {
        const next = root.getAttribute("data-state") === v ? "" : v;
        if (next) root.setAttribute("data-state", next); else root.removeAttribute("data-state");
        document.dispatchEvent(new CustomEvent("mockstate", { detail: next }));
      } else {
        root.setAttribute("data-" + k, v);
        store.set(k, v);
      }
      sync();
    });
    sync();
  }

  /* Tiện ích cho từng màn */
  window.TC = {
    icon(name, cls) { return `<svg class="i ${cls || ""}" aria-hidden="true"><use href="#i-${name}"/></svg>`; },
    fill(root) {
      (root || document).querySelectorAll("[data-icon]").forEach((el) => {
        if (!el.querySelector(":scope > svg.i")) el.insertAdjacentHTML("afterbegin", TC.icon(el.dataset.icon, el.dataset.iconClass));
      });
    },
    isTyping(e) { const t = e.target; return t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable); },
  };
  ready(() => TC.fill());
})();
