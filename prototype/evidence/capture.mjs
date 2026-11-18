#!/usr/bin/env node
/* 真实视口取证：通过 Chrome DevTools Protocol 设置精确设备尺寸并截图 / 取指标。
   仅本机 127.0.0.1，无外部网络；Chrome 以无头模式启动，不显示窗口。 */
import { spawn } from 'node:child_process';
import { writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const ROOT = resolve(import.meta.dirname, '..');
const PORT = 9399;
const targets = [
  { name: 'viewport-1440-today', width: 1440, height: 900, mobile: false, hash: '' },
  { name: 'viewport-1440-trends', width: 1440, height: 900, mobile: false, hash: '#trends' },
  { name: 'viewport-1440-sleep-day', width: 1440, height: 900, mobile: false, hash: '#sleep-day' },
  { name: 'viewport-375-today', width: 375, height: 812, mobile: true, hash: '' },
  { name: 'viewport-375-health', width: 375, height: 812, mobile: true, hash: '#health' },
  { name: 'viewport-375-sleep-day', width: 375, height: 812, mobile: true, hash: '#sleep-day' },
];

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const tmp = await mkdtemp(join(tmpdir(), 'sw-cdp-'));
const chrome = spawn(CHROME, [
  '--headless=new', '--no-first-run', '--disable-gpu', '--no-sandbox',
  '--allow-file-access-from-files', `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${tmp}`, '--window-size=1440,900', 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let chromeErr = '';
chrome.stderr.on('data', d => { chromeErr += String(d); });

async function getPageWs() {
  for (let i = 0; i < 60; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
      const page = list.find(t => t.type === 'page');
      if (page) return page.webSocketDebuggerUrl;
    } catch (_) { /* 启动中 */ }
    await sleep(200);
  }
  throw new Error(`Chrome CDP 未就绪：${chromeErr.slice(-400)}`);
}

const wsUrl = await getPageWs();
const ws = new WebSocket(wsUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let seq = 0;
const pending = new Map();
const events = [];
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve: r, reject: j } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? j(new Error(JSON.stringify(msg.error))) : r(msg.result);
  } else if (msg.method) events.push(msg);
};
const send = (method, params = {}) => new Promise((r, j) => {
  const id = ++seq;
  pending.set(id, { resolve: r, reject: j });
  ws.send(JSON.stringify({ id, method, params }));
});

await send('Page.enable');
await send('Runtime.enable');
const report = { generatedAt: new Date().toISOString(), tool: 'Chrome CDP Emulation.setDeviceMetricsOverride', captures: [] };
for (const t of targets) {
  await send('Emulation.setDeviceMetricsOverride', { width: t.width, height: t.height, deviceScaleFactor: 1, mobile: t.mobile });
  events.length = 0;
  // 每次使用唯一查询参数强制完整加载，避免同文档 hash 导航导致截图取到旧合成帧
  await send('Page.navigate', { url: `file://${ROOT}/index.html?capture=${encodeURIComponent(t.name)}${t.hash}` });
  for (let i = 0; i < 50 && !events.some(e => e.method === 'Page.loadEventFired'); i++) await sleep(100);
  // 同文档 hash 变化不会重新触发 load，显式切换页面以确保取证的是目标页
  if (t.hash) {
    await send('Runtime.evaluate', { expression: `window.__PROTOTYPE__.showScreen(${JSON.stringify(t.hash.slice(1))}, {silent:true})`, returnByValue: true });
  }
  await sleep(350);
  const metrics = await send('Runtime.evaluate', {
    expression: `JSON.stringify((() => { const s=document.getElementById('screen-scroller'); const p=document.getElementById('phone'); const bar=document.getElementById('tabbar'); return { innerWidth, innerHeight, screen: window.__PROTOTYPE__.activeScreen, phoneRect: p.getBoundingClientRect().toJSON(), tabbarRect: bar.hidden ? null : bar.getBoundingClientRect().toJSON(), scrollerClientWidth: s.clientWidth, activeScreenScrollWidth: document.querySelector('.screen.is-active').scrollWidth, bodyScrollWidth: document.body.scrollWidth, horizontalOverflow: document.body.scrollWidth > innerWidth + 1 }; })())`,
    returnByValue: true,
  });
  const shot = await send('Page.captureScreenshot', { format: 'png', fromSurface: true, captureBeyondViewport: false });
  const file = join(ROOT, 'evidence', `${t.name}.png`);
  await writeFile(file, Buffer.from(shot.data, 'base64'));
  const errors = events.filter(e => e.method === 'Runtime.exceptionThrown').map(e => e.params?.exceptionDetails?.text || 'exception');
  report.captures.push({ name: t.name, requested: `${t.width}x${t.height}`, mobile: t.mobile, file, metrics: JSON.parse(metrics.result.value), pageErrors: errors });
}
await writeFile(join(ROOT, 'evidence', 'viewport-report.json'), JSON.stringify(report, null, 2) + '\n', 'utf8');
console.log(JSON.stringify(report, null, 2));
ws.close();
chrome.kill('SIGTERM');
await sleep(300);
await rm(tmp, { recursive: true, force: true });
