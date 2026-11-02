// node check.mjs DIR: serves DIR (index.html, page.js, page.wasm), loads
// it in headless Chromium, clicks the button, calls the exported functions.
// Needs playwright: PLAYWRIGHT_DIR (its node_modules' parent) and
// PLAYWRIGHT_BROWSERS_PATH.
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
const port = server.address().port;
const browser = await chromium.launch();
const page = await browser.newPage();
const logs = [];
page.on('console', (m) => logs.push(m.text()));
page.on('pageerror', (e) => logs.push('page error: ' + e.message));
await page.goto(`http://localhost:${port}/`);
await page.waitForFunction(() => document.getElementById('out')?.textContent === 'ready', null, { timeout: 30000 });
await page.click('#button');
await page.click('#button');
console.log('after clicks:', await page.textContent('#out'));
console.log('ocamlAdd(2, 3) =', await page.evaluate(() => ocamlAdd(2, 3)));
console.log('ocamlUpper("abc") =', await page.evaluate(() => ocamlUpper('abc')));
console.log('console:', logs.join(' | '));
await browser.close();
server.close();
