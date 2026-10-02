// render.mjs
// Renders every scene JSON in tools/preview/out/ (written by export.luau) to a PNG sheet
// using three.js in headless Chromium.  Usage (from tools/preview):
//   npm install && node render.mjs [scene-name-filter]
import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
let chromium;
try {
  ({ chromium } = require("playwright"));
} catch {
  ({ chromium } = require("/opt/node22/lib/node_modules/playwright"));
}

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(here, "out");
const filter = process.argv[2];

const TYPES = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json" };
const server = http.createServer((req, res) => {
  const file = path.join(here, decodeURIComponent(req.url.split("?")[0]));
  if (!file.startsWith(here) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404);
    res.end();
    return;
  }
  res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
  fs.createReadStream(file).pipe(res);
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const port = server.address().port;

const browser = await chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const page = await browser.newPage();
page.on("console", (msg) => { if (msg.type() === "error") console.error("page:", msg.text()); });
page.on("pageerror", (err) => console.error("page error:", err.message));
await page.goto(`http://127.0.0.1:${port}/viewer.html`);
await page.waitForFunction(() => window.ready === true, null, { timeout: 30000 });

const files = fs.readdirSync(outDir).filter((f) => f.endsWith(".json") && (!filter || f.includes(filter)));
for (const file of files) {
  const scene = JSON.parse(fs.readFileSync(path.join(outDir, file), "utf8"));
  const dataUrl = await page.evaluate((s) => window.renderScene(s), scene);
  const png = Buffer.from(dataUrl.split(",")[1], "base64");
  const target = path.join(outDir, file.replace(/\.json$/, ".png"));
  fs.writeFileSync(target, png);
  console.log("rendered", path.relative(process.cwd(), target));
}

await browser.close();
server.close();
