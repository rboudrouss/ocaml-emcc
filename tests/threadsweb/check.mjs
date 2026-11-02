// node check.mjs DIR: serves DIR (index.html, th.js, th.wasm) cross-origin
// isolated (COOP/COEP: SharedArrayBuffer, hence threads), loads it in
// headless Chromium and prints what the program printed.  Needs playwright:
// PLAYWRIGHT_DIR (its node_modules' parent) and PLAYWRIGHT_BROWSERS_PATH.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
const require = createRequire(path.join(process.env.PLAYWRIGHT_DIR, 'x.js'));
const { chromium } = require('playwright');
const dir = process.argv[2];
const types = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm' };
const server = http.createServer((req, res) => {
  const f = path.join(dir, req.url === '/' ? 'index.html' : req.url);
  if (!fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, {
    'Content-Type': types[path.extname(f)] || 'application/octet-stream',
    'Cross-Origin-Opener-Policy': 'same-origin',
    'Cross-Origin-Embedder-Policy': 'require-corp',
  });
  res.end(fs.readFileSync(f));
}).listen(0);
const port = server.address().port;
const browser = await chromium.launch();
const page = await browser.newPage();
const out = [];
let finished;
const done = new Promise((resolve) => (finished = resolve));
page.on('console', (m) => {
  if (m.type() === 'log') out.push(m.text());
  else if (m.type() === 'error') console.error(m.text());
  if (m.text() === 'done') finished();
});
page.on('pageerror', (e) => { console.error('page error: ' + e.message); finished(); });
await page.goto(`http://localhost:${port}/`);
await Promise.race([done, new Promise((r) => setTimeout(r, 60000))]);
console.log(out.join('\n'));
await browser.close();
server.close();
