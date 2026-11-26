// Kiểm tương phản WCAG cho các cặp chữ trên nền trong tokens.css: node design/tools/contrast.cjs
const fs = require("fs"), path = require("path");
const css = fs.readFileSync(path.join(__dirname, "..", "tokens.css"), "utf8");
const block = (sel) => { const m = css.match(new RegExp(sel.replace(/[[\]"]/g, (c) => "\\" + c) + "\\s*\\{([\\s\\S]*?)\\n\\}")); const o = {}; m && m[1].replace(/--([\w-]+):\s*(#[0-9a-f]{6})/gi, (_, k, v) => (o[k] = v)); return o; };
const dark = block(":root"), light = { ...dark, ...block(':root[data-theme="light"]') };
const lum = (h) => { const c = [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255).map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]; };
const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
const PAIRS = [
  ["text", "bg-panel", 4.5], ["text-2", "bg-panel", 4.5], ["text-3", "bg-panel", 4.5], ["text-3", "bg-window", 4.5], ["text-3", "bg-stage", 4.5], ["text-3", "bg-raised", 4.5],
  ["text-2", "bg-raised", 4.5], ["accent", "bg-panel", 4.5], ["accent", "bg-stage", 4.5], ["on-accent", "accent-fill", 4.5],
  ["warn", "bg-panel", 4.5], ["late", "bg-panel", 4.5], ["late-ink", "late", 4.5], ["freeze", "bg-panel", 4.5], ["ok", "bg-panel", 4.5], ["danger", "bg-overlay", 4.5], ["on-danger", "danger-fill", 4.5],
  ["line-strong", "bg-panel", 1.5],
];
let fail = 0; const rows = [];
for (const [fg, bg, min] of PAIRS) {
  const d = ratio(dark[fg], dark[bg]), l = ratio(light[fg], light[bg]);
  const ok = d >= min && l >= min; if (!ok) fail++;
  rows.push(`| \`--${fg}\` trên \`--${bg}\` | ${d.toFixed(2)} | ${l.toFixed(2)} | ${min} | ${ok ? "Đạt" : "Chưa đạt"} |`);
}
console.log("| Cặp | Tối | Sáng | Tối thiểu | Kết quả |\n| --- | --- | --- | --- | --- |\n" + rows.join("\n"));
process.exit(fail ? 1 : 0);
