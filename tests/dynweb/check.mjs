// node check.mjs DIR: serves DIR, loads its index.html in headless Chromium
// and prints what the program writes, until it prints "end" (see
// tests/jsdom/check.mjs for PLAYWRIGHT_DIR and PLAYWRIGHT_BROWSERS_PATH).
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
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' });
  res.end(fs.readFileSync(f));
}).listen(0);
const browser = await chromium.launch();
const page = await browser.newPage();
const logs = [];
page.on('console', (m) => { if (m.type() !== 'error' || !/Failed to load resource/.test(m.text())) logs.push(m.text()); });
page.on('pageerror', (e) => logs.push('page error: ' + e.message));
await page.goto(`http://localhost:${server.address().port}/`);
for (let i = 0; i < 300 && !logs.includes('end'); i++) await page.waitForTimeout(100);
console.log(logs.join('\n'));
await browser.close();
server.close();
