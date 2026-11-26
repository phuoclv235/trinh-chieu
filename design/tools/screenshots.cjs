// Chụp ảnh mẫu: node design/tools/screenshots.cjs [màn...]
// 5 màn x 3 cỡ cửa sổ (1280, 1512, 1920) x sáng tối, deviceScaleFactor 2.
// Báo lỗi console, tràn ngang và chữ bị cắt mà không có chú giải (title hoặc aria-label).
const { chromium } = require("playwright");
const path = require("path");
const dir = path.resolve(__dirname, "..");
const SCREENS = ["live", "editor", "library", "settings-outputs", "stage"];
const SIZES = [[1280, 800], [1512, 945], [1920, 1080]];
const only = process.argv.slice(2);
(async () => {
  const browser = await chromium.launch();
  const problems = [];
  for (const s of only.length ? only : SCREENS) for (const [w, h] of SIZES) for (const theme of ["dark", "light"]) {
    const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 2 });
    page.on("console", (m) => m.type() === "error" && problems.push(`${s} ${w} ${theme}: console ${m.text()}`));
    page.on("pageerror", (e) => problems.push(`${s} ${w} ${theme}: ${e.message}`));
    await page.goto(`file://${dir}/${s}.html?theme=${theme}&shot=1`);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    const r = await page.evaluate(() => {
      const out = { overflow: document.documentElement.scrollWidth > innerWidth, clipped: [] };
      document.querySelectorAll(".truncate, .row__title, .row__sub, .slide-card__label, .table td, .node__main span, .out-node span, .preview__screen").forEach((el) => {
        if (el.scrollWidth > el.clientWidth + 1 && !el.closest("[title],[aria-label]") && !el.title) out.clipped.push(el.textContent.trim().slice(0, 40));
      });
      return out;
    });
    if (r.overflow) problems.push(`${s} ${w} ${theme}: tràn ngang`);
    if (r.clipped.length && theme === "dark") problems.push(`${s} ${w}: chữ bị cắt không chú giải: ${r.clipped.slice(0, 4).join(" | ")}${r.clipped.length > 4 ? ` (+${r.clipped.length - 4})` : ""}`);
    await page.screenshot({ path: `${dir}/screenshots/${s}-${w}-${theme === "dark" ? "toi" : "sang"}.png` });
    await page.close();
  }
  console.log(problems.length ? problems.join("\n") : "Không có lỗi");
  await browser.close();
})();
