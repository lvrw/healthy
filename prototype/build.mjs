#!/usr/bin/env node
/* StressWatch UI 原型 · 确定性构建器（仅 Node 标准库）
   输入：src/ 下的页面片段、样式、脚本、页面规格；docs/ 下的 53 张源图（只读取哈希，不作为背景）
   输出：可直接用 file:// 打开的 index.html、prototype.css、prototype.js 及验收材料 */
import { readFile, writeFile, readdir, stat } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { resolve, join, basename } from 'node:path';
import { pathToFileURL } from 'node:url';
import { icon } from './src/icons.mjs';
import { expandCharts } from './src/charts.mjs';
import { screens } from './src/screens.mjs';

const ROOT = resolve(import.meta.dirname);
const SRC = join(ROOT, 'src');
const DOCS = resolve(ROOT, '..', 'docs');
const RUNTIME_LINT = '/Users/lvrongwang/.workbuddy/plugins/cache/experts/screenshot-ui-prototype/0.1.6/skills/screenshot-ui-prototype/runtime/code/prototype-builder/src/render.mjs';
const VERSION = '1.0.0';
const sha = (b) => createHash('sha256').update(b).digest('hex');
const esc = (s) => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
const assert = (ok, msg) => { if (!ok) throw new Error(`BUILD BLOCKED: ${msg}`); };
const read = (p) => readFile(p, 'utf8');

/* ---------- Phase 3 · 构建期数据 / 资源接入（全部发生在生成 HTML 之前） ----------
   1) assets/data/chart-series.json 是 50 条序列的唯一数值真源；按 data-series 注入 data-*。
   2) assets/manifest.json + assets/ill|art/*.svg 是 24 个插画/配图的唯一来源；按 data-art 内联。
   两者都在构建期完成，成品 index.html 仍可直接 file:// 打开，运行期无 fetch / 外链。 */
const ASSETS = join(ROOT, 'assets');
const ATTR_RE = /([a-z][a-z0-9-]*)\s*=\s*"([^"]*)"/gi;
const parseAttrs = (raw) => { const o = {}; for (const m of String(raw).matchAll(ATTR_RE)) o[m[1].toLowerCase()] = m[2]; return o; };
const escAttr = (s) => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
const serializeAttrs = (o) => Object.entries(o).map(([k, v]) => ` ${k}="${escAttr(v)}"`).join('');

// manifest 里用 CSS 变量名标注配色，这里只映射到 charts.mjs 的色板键（不产生新色值）
const COLOR_TOKEN = {
  '--green': 'green', '--lav': 'lavender', '--orange': 'orange', '--pink': 'pink',
  '--teal': 'teal', '--sky': 'sky', '--purple': 'purple', '--gray-line': 'grayLine',
  '--red': 'red', '--faint': 'faint', '--gray': 'gray', '--white': 'white',
};
const colorToken = (name) => COLOR_TOKEN[name] || String(name || 'grayLine').replace(/^--/, '');

// 02 §5.4：只有这些序列允许新增 data-min / data-max，其余 data-max/min/avg/ylabels/labels 保持现值
const MIN_MAX_IDS = new Set([
  'sleep-vitals-hrv-line', 'sleep-vitals-hr-line', 'sleep-vitals-resp-line',
  'sleep-vitals-spo2-line', 'sleep-vitals-wrist-line', 'today-detail-rhr-wave',
]);

// 主理人裁定：需要落在 DOM 的口径副本（Q19 / Q21 / Q12 / Q10 / Q11 / 5 次采样口径等）
// 只新增说明文字，不改动任何截图可见文案、数值与 SVG 内文字。
const CALIBER_NOTES = {
  'body-age-disc': '口径：中心 34.2 岁为页面可见读数；外圈 2 段弧与 46 个彩点为纯装饰、无数据语义。单位 岁。',
  'today-detail-hrv-line': '口径：按 DOM 图例，虚线=今日平均HRV、实线=近30日平均HRV；40 / 30 与可见文案保持原样。5 点 = 当日 5 次采样，3 个标签为时间范围锚点（中间 05:00 为截图可见文案，原样保留）。单位 ms。',
  'today-hrv-line': '口径：5 次采样 + 3 个时间范围锚点；每点 = 1 次 HRV 采样。单位 ms。',
  'day-hrv-line': '口径：5 次采样 + 3 个时间范围锚点；每点 = 1 次 HRV 采样。单位 ms。',
  'today-stress-hist': '口径：74 柱 = 74 次采样；柱色按 1–20 / 21–60 / 61–80 / 81–100 阈值；紫色带为睡眠时段示意定位。',
  'day-hrv-hist': '口径：74 柱 = 74 次采样；柱色按 1–20 / 21–60 / 61–80 / 81–100 阈值；紫色带为睡眠时段示意定位。',
  'trends-week-stress-bars': '口径：第 7 柱（11月8日）无数据，以 --faint 柱高 0 表示。',
  'trends-week-hrv-line': '口径：11月8日无数据，以空点表示；均值按 6 个有效日计算。',
  'trends-week-rhr-line': '口径：11月8日无数据，以空点表示；均值按 6 个有效日计算。',
  'trends-week-stress-dots': '口径：0 编码为空点（无采样）；11月8日全天无数据。',
  'sleep-vitals-hrv-line': '口径：每点 = 1 日，共 14 日；13 个逐日刻度中首点无标签。单位 ms。',
  'sleep-vitals-hr-line': '口径：每点 = 1 日，共 14 日；13 个逐日刻度中首点无标签。单位 bpm。',
  'sleep-vitals-resp-line': '口径：每点 = 1 日，共 14 日；13 个逐日刻度中首点无标签。单位 br/min。',
  'sleep-vitals-spo2-line': '口径：每点 = 1 日，共 14 日；13 个逐日刻度中首点无标签。单位 %。',
  'sleep-vitals-wrist-line': '口径：每点 = 1 日，共 14 日；13 个逐日刻度中首点无标签。单位 °C。',
  'sleep-month-continuity-bars': '口径：7 柱均为有效值；第 7 柱为 11月7日有效采样，非无数据。',
  'today-detail-rhr-wave': '口径：y 轴 90–0 BPM 为近似刻度；波形是近 60 日平均静息心率参考序列，今日无数据。',
  'vo2max-line': '口径：28–67 为 y 轴刻度范围，不是数据值域；浅紫折线与首点白点按截图既有例外保留。',
  'sleep-day-ring': '口径：外环 = 睡眠时长 / 目标，内环 = 睡眠质量 / 100；数值来自截图可见值。',
};

// 02 §2.3：来源只允许两种，时间只取 7 种页面可见值（去重后 5 个字面量）
const SOURCE_NOTE_RE = /^数据来自 (原型演示数据|截图可见值) · 更新于 (2026-11-07 10:05|2026-11-07|2026-11-08|2026-11-07（每日凌晨更新）|2026-11-06)$/;

/** 构建期校验：50 条序列、同源序列严格同值、null 点数、check 校验值。 */
function verifySeriesData(data) {
  assert(data.version && Array.isArray(data.series), 'chart-series.json 结构不符合契约');
  assert(data.series.length === 50, `chart-series.json 应有 50 条序列，实际 ${data.series.length}`);
  const byId = new Map(data.series.map(s => [s.id, s]));
  assert(byId.size === 50, 'chart-series.json 存在重复 id');
  let nullCount = 0;
  for (const s of data.series) {
    assert(SOURCE_NOTE_RE.test(s.sourceNote), `${s.id} 的来源角标不符合 02 §2.3 规则：${s.sourceNote}`);
    assert(s.aria && s.caliber, `${s.id} 缺少 aria / caliber`);
    const numeric = Array.isArray(s.points) && s.points.length && s.points.every(p => p === null || typeof p === 'number');
    if (numeric) nullCount += s.points.filter(p => p === null).length;
    const c = s.check;
    if (!c || !numeric) continue;
    const valid = s.points.filter(p => p !== null);
    if (c.sampleCount !== undefined) assert(c.sampleCount === s.points.length, `${s.id} sampleCount 与点数不符`);
    if (c.barCount !== undefined) assert(c.barCount === s.points.length, `${s.id} barCount 与点数不符`);
    if (c.mean !== undefined) assert(Math.abs(valid.reduce((a, b) => a + b, 0) / valid.length - c.mean) < 0.06, `${s.id} 均值与 check 不符`);
    if (c.last !== undefined) assert(Math.abs(s.points.at(-1) - c.last) < 1e-6, `${s.id} 末点与 check 不符`);
    if (c.max !== undefined) assert(Math.abs(Math.max(...valid) - c.max) < 1e-6, `${s.id} 最大值与 check 不符`);
    if (c.min !== undefined) assert(Math.abs(Math.min(...valid) - c.min) < 1e-6, `${s.id} 最小值与 check 不符`);
  }
  // 分段 / 双系列 / 聚合图的合计校验
  for (const s of data.series) {
    const c = s.check;
    if (!c || !Array.isArray(s.points) || !s.points.length || typeof s.points[0] !== 'object' || Array.isArray(s.points[0])) continue;
    const sum = (key) => s.points.reduce((a, p) => a + (Number(p[key]) || 0), 0);
    if (c.segmentCount !== undefined) assert(c.segmentCount === s.points.length, `${s.id} segmentCount 不符`);
    for (const [k, field] of [['sumPercent', 'percent'], ['sumWidthPct', 'widthPct'], ['sumDays', 'days'], ['sumTimes', 'times'], ['sumMinutes', 'minutes'], ['sumTotalHours', 'totalHours'], ['sumDurationMinutes', 'durationMin']]) {
      if (c[k] !== undefined) assert(Math.abs(sum(field) - c[k]) < 1e-6, `${s.id} ${k} 与 check 不符`);
    }
  }
  assert(nullCount === 3, `JSON 中应有且仅有 3 个 null 点，实际 ${nullCount}`);
  const shared = data.sharedSeries || {};
  // 同源序列严格同值（HRV5 / HIST74 / DOTS7x24 / VITAL14）
  const same = (a, b, label) => assert(JSON.stringify(a) === JSON.stringify(b), `${label} 同源序列不同值`);
  for (const id of ['today-hrv-line', 'today-detail-hrv-line', 'day-hrv-line']) same(byId.get(id).points, shared.HRV5.values, 'HRV5');
  for (const id of ['today-stress-hist', 'day-hrv-hist']) same(byId.get(id).points, shared.HIST74.values, 'HIST74');
  same(byId.get('trends-week-stress-dots').points, shared.DOTS7x24.values, 'DOTS7x24');
  const vitalMap = { hrv: 'hrv', hr: 'hr', resp: 'resp', spo2: 'spo2', wrist: 'wrist' };
  for (const [key, short] of Object.entries(vitalMap)) {
    same(byId.get(`sleep-vitals-${short}-line`).points, shared.VITAL14[key].v, `VITAL14.${key}`);
    same(byId.get(`today-vital-mini-${short}`).points, shared.VITAL14[key].v, `VITAL14.${key} mini(today)`);
    same(byId.get(`sleep-day-vital-mini-${short}`).points, shared.VITAL14[key].v, `VITAL14.${key} mini(sleep-day)`);
  }
  return byId;
}

/** 01 §9 R2：disc 的 46 个装饰点必须与口径真源逐点同值，且不得被删减或重排。
    生成侧真源 = charts.mjs 的 disc()（rng(5)）；口径侧真源 = sharedSeries.discDecorativeDots.dots。
    这里只做校验，不重算、不注入 dataset，中心 13/39/11px SVG 文字也不改。 */
function verifyDiscDecorativeDots(html, data) {
  const dots = data.sharedSeries?.discDecorativeDots?.dots;
  assert(Array.isArray(dots) && dots.length === 46, 'sharedSeries.discDecorativeDots.dots 应恰好 46 项');
  assert(data.series.find(s => s.id === 'body-age-disc')?.check?.decorativeDotCount === 46,
    'body-age-disc.check.decorativeDotCount 应为 46（位于 series[].check，不是顶层）');
  const disc = html.match(/<div\s+class="chart chart-disc"[\s\S]*?<\/div>/i);
  assert(disc, '未找到 chart-disc 的展开结果');
  // 装饰点是 disc() 中唯一带 opacity=".8" 的 circle，其余为表盘底圆 / 弧 / 中心圆
  const circles = [...disc[0].matchAll(/<circle[^>]*opacity="\.8"[^>]*>/gi)].map(m => m[0]);
  assert(circles.length === 46, `chart-disc 装饰点应恰好 46 个，实际 ${circles.length}`);
  const pick = (s, key) => { const m = new RegExp(`${key}="([^"]+)"`).exec(s); return m ? m[1] : ''; };
  let diff = 0;
  circles.forEach((c, i) => {
    const j = dots[i];
    const same = j && Number(pick(c, 'cx')) === Number(j.cx) && Number(pick(c, 'cy')) === Number(j.cy)
      && Number(pick(c, 'r')) === Number(j.r) && String(pick(c, 'fill')).toLowerCase() === String(j.color).toLowerCase();
    if (!same) diff++;
  });
  assert(diff === 0, `chart-disc 装饰点与口径真源有 ${diff} 处差异`);
  return 46;
}

/** 把一条序列的 points / colors / segments / min / max 注入到图表占位元素的 data-*。 */
function applySeries(a, s, data) {
  const pts = s.points;
  // aria 用 JSON 填实文案；口径 / 来源由 DOM 的 .chart-source 承担，不写进 SVG
  a['data-aria'] = s.aria;
  switch (s.chartKind) {
    case 'step':
      a['data-segments'] = pts.map(p => `${p.startPct}:${p.widthPct}:${p.level}:${p.kind}`).join('|');
      return;
    case 'stack':
    case 'capsule':
      a['data-segments'] = pts.map(p => `${p.percent}:${colorToken(p.color)}`).join('|');
      return;
    case 'dualbars':
      a['data-values'] = pts.map(p => p.remHours).join(',');
      a['data-values-b'] = pts.map(p => p.deepHours).join(',');
      return;
    case 'ring':
      a['data-outer-value'] = String(pts.find(p => p.ring === 'outer').correctedArc);
      a['data-inner-value'] = String(pts.find(p => p.ring === 'inner').correctedArc);
      return;
    case 'disc':
      a['data-seed'] = '5'; // 仅 46 个纯装饰彩点使用 seed，口径注明「纯装饰、无数据语义」
      return;
    case 'dots':
      delete a['data-seed']; // 取消伪随机，改注入显式 7×24 编码矩阵
      a['data-matrix'] = pts.map(row => row.join(',')).join('|');
      return;
    case 'hist':
      delete a['data-seed']; // 取消 seed="11"，改注入 74 个显式值；柱色由 charts.mjs 阈值判定
      a['data-values'] = pts.join(',');
      return;
    default: {
      const nullIdx = [];
      // null → 0（绝不把文本 null 写进 data-values，nums() 会丢弃并造成点数错位）
      a['data-values'] = pts.map((v, i) => { if (v === null) { nullIdx.push(i); return 0; } return v; }).join(',');
      if (nullIdx.length) {
        const colors = String(a['data-colors'] || '').split(',').map(x => x.trim());
        nullIdx.forEach(i => { while (colors.length <= i) colors.push('gray'); colors[i] = 'faint'; });
        a['data-colors'] = colors.join(',');
        a['data-aria'] += nullIdx.map(i => `，第 ${i + 1} 点无数据`).join('');
      }
      if (MIN_MAX_IDS.has(s.id)) {
        a['data-min'] = String(s.yAxis.min);
        a['data-max'] = String(s.yAxis.max);
      }
      // JSON 若显式给出 colors 则以它为准（HRV5 三条同源线由 sharedSeries 严格对齐）
      if (Array.isArray(s.colors)) a['data-colors'] = s.colors.join(',');
      if (s.id.startsWith('today-') || s.id.startsWith('day-hrv-') || s.id.startsWith('today-detail-')) {
        const hrv5 = ['today-hrv-line', 'today-detail-hrv-line', 'day-hrv-line'];
        if (hrv5.includes(s.id)) a['data-colors'] = data.sharedSeries.HRV5.colors.join(',');
      }
    }
  }
}

/** 扫描 50 处 <div class="chart">，按 data-series 注入数据（保留 data-series 供口径注记使用）。 */
function injectChartSeries(html, data) {
  const byId = new Map(data.series.map(s => [s.id, s]));
  const seen = new Set();
  const out = html.replace(/<div\s+class="chart"([^>]*?)><\/div>/g, (full, raw) => {
    const a = parseAttrs(raw);
    const id = a['data-series'];
    assert(id, `图表占位缺少 data-series：${full.slice(0, 100)}`);
    assert(byId.has(id), `data-series 未在 chart-series.json 中定义：${id}`);
    assert(!seen.has(id), `data-series 重复：${id}`);
    seen.add(id);
    applySeries(a, byId.get(id), data);
    assert(!/\bnull\b/.test(a['data-values'] || ''), `${id} 的 data-values 残留 null 文本`);
    // 除 body-age-disc 的装饰点外，不允许任何测量类图表使用 data-seed
    if (a['data-seed']) assert(id === 'body-age-disc', `${id} 不应使用 data-seed`);
    return `<div class="chart"${serializeAttrs(a)}></div>`;
  });
  assert(seen.size === 50, `应注入 50 处图表序列，实际 ${seen.size}`);
  return { html: out, count: seen.size, ids: [...seen] };
}

/** 来源角标 / 口径说明一律落 DOM：按卡片聚合，避免在 60px 宽的迷你图容器内换行。
    01 §9 R1 / 02 §6-8：统一用 note-source-* 类；.chart-source（工程契约）与
    .source-note（02 §2.3）保留为同值兼容别名。title 存全文，单行省略时仍可读，
    且完整文案始终在 DOM 里，不写进 SVG。 */
function injectChartNotes(html, data) {
  const byId = new Map(data.series.map(s => [s.id, s]));
  const note = (cls, text) => `<p class="${cls}" title="${esc(text)}">${esc(text)}</p>`;
  const renderNotes = (ids) => {
    const lines = [];
    [...new Set(ids.map(id => byId.get(id).sourceNote))]
      .forEach(t => lines.push(note('chart-source source-note note-source-data', t)));
    ids.forEach(id => { if (CALIBER_NOTES[id]) lines.push(note('chart-source note-source-caliber', CALIBER_NOTES[id])); });
    return lines.join('');
  };
  // 卡片内的图表：在 </article> 前统一放来源 / 口径，图表自身不再重复标注
  let out = html.replace(/<article\s+class="card[^"]*"[^>]*>[\s\S]*?<\/article>/gi, (block) => {
    const ids = [...block.matchAll(/\bdata-series="([^"]+)"/g)].map(m => m[1]);
    if (!ids.length) return block;
    const marked = block.replace(/\bdata-series="/g, 'data-chart-series="');
    return marked.replace(/<\/article>\s*$/i, `${renderNotes(ids)}</article>`);
  });
  // 非卡片容器（sleep-hero 双环 / age-hero 圆盘 / sheet 正文）：直接跟在图表后面
  out = out.replace(/<div\s+class="chart"([^>]*?)><\/div>/g, (full, raw) => {
    const a = parseAttrs(raw);
    if (!a['data-series']) return full;
    return full + renderNotes([a['data-series']]);
  });
  return out;
}

/** 读取资源清单与 24 个裸 <svg> 片段（只读 assets/，不生成任何资源文件）。 */
async function loadArtManifest() {
  const manifestPath = join(ASSETS, 'manifest.json');
  try { await stat(manifestPath); } catch { assert(false, 'assets/manifest.json 缺失（等待资源侧文件后复验）'); }
  const manifest = JSON.parse(await read(manifestPath));
  assert(Array.isArray(manifest.resources) && manifest.resources.length === 24, `manifest.resources 应恰好 24 条，实际 ${manifest.resources?.length}`);
  const byId = new Map(manifest.resources.map(r => [r.id, r]));
  assert(byId.size === 24, 'manifest.resources 存在重复 id');
  assert(Array.isArray(manifest.charts), 'manifest.charts 应为数组');
  // 02 §6-1：manifest.charts 只存 series[].id 引用，不复制数值副本；并集须覆盖全部 50 条
  const seriesIds = new Set(manifest.charts.flatMap(c => Array.isArray(c.seriesIds) ? c.seriesIds : []));
  assert(seriesIds.size === 50, `manifest.charts.seriesIds 应覆盖 50 条序列，实际 ${seriesIds.size}`);
  // 01 §9 R1 / 02 §2.2：darkVariant: reserved 为资源侧字段；此处只统计、不代写 assets/ 文件
  const darkVariantReserved = manifest.resources.filter(r => r.darkVariant === 'reserved').length;
  const resolveArtFile = async (p) => {
    for (const c of [resolve(ROOT, p), join(ASSETS, p), join(ASSETS, basename(p))]) {
      try { await stat(c); return c; } catch { /* 继续尝试下一个候选路径 */ }
    }
    assert(false, `资源 SVG 文件不存在：${p}`);
  };
  const readOne = async (p) => {
    const raw = (await read(await resolveArtFile(p))).trim();
    assert(/^<svg\b/i.test(raw), `资源不是裸 <svg> 片段：${p}`);
    assert(!/<script\b|<image\b|<foreignObject\b|<iframe\b/i.test(raw), `资源含禁用元素：${p}`);
    assert(!/(?:src|href)=["'](?:https?:)?\/\//i.test(raw), `资源含外链：${p}`);
    return raw;
  };
  const svgById = new Map();
  for (const r of manifest.resources) {
    assert(r.id && r.path, 'manifest.resources 条目缺少 id / path');
    svgById.set(r.id, await readOne(r.path));
    // 变体文件是可选的；data-art="id--variant" 优先用变体，否则回退到基础资源
    for (const v of (Array.isArray(r.variants) ? r.variants : [])) {
      if (typeof v === 'string' && /\.svg$/i.test(v)) svgById.set(basename(v).replace(/\.svg$/i, ''), await readOne(v));
      else if (v && typeof v === 'object' && v.path) {
        const key = v.id || (v.suffix ? `${r.id}--${String(v.suffix).replace(/^--/, '')}` : basename(v.path).replace(/\.svg$/i, ''));
        svgById.set(key, await readOne(v.path));
      }
    }
  }
  return { byId, svgById, manifest, seriesIds, darkVariantReserved };
}

/** 把 data-art 占位替换为内联 SVG；容器上写 data-origin，且移除 data-art 本身。 */
function expandArtResources(html, art) {
  const used = new Set();
  let count = 0;
  const out = html.replace(/<(div|figure|span|svg|p|section)\b([^>]*?)\bdata-art="([^"]+)"([^>]*)>([\s\S]*?)<\/\1>/gi, (m, tag, pre, id, post, inner) => {
    const base = id.split('--')[0];
    const res = art.byId.get(id) || art.byId.get(base);
    assert(res, `data-art 未在 manifest 中定义：${id}`);
    const svg = art.svgById.get(id) || art.svgById.get(base) || art.svgById.get(res.id);
    assert(svg, `资源 SVG 缺失：${id}`);
    const origin = (res.origin === 'replica' || res.origin === 'screenshot') ? 'screenshot' : 'stylized';
    used.add(res.id);
    count++;
    const open = m.slice(0, m.indexOf('>') + 1).replace(/\s+data-art="[^"]*"/i, ` data-origin="${origin}"`);
    // 文章配图：SVG 插到 figcaption 之前；其它容器：直接作为内容插入
    const body = /<figcaption\b/i.test(inner) ? inner.replace('<figcaption', `${svg}<figcaption`) : `${inner}${svg}`;
    return `${open}${body}</${tag}>`;
  });
  return { html: out, count, used };
}

async function main() {
  /* ---------- 1. 输入校验：素材存在、映射完整且不重复 ---------- */
  const docFiles = (await readdir(DOCS)).filter(f => f.toLowerCase().endsWith('.jpeg')).sort();
  assert(docFiles.length === 53, `docs 图片数量应为 53，实际 ${docFiles.length}`);
  const sourceHashes = {};
  for (const f of docFiles) sourceHashes[f] = sha(await readFile(join(DOCS, f)));
  const mapped = screens.flatMap(s => s.sources);
  assert(mapped.length === 53, `截图映射数应为 53，实际 ${mapped.length}`);
  assert(new Set(mapped).size === 53, '截图映射存在重复');
  for (const f of mapped) assert(sourceHashes[f], `映射的截图不存在：${f}`);
  assert(new Set(docFiles).size === new Set(mapped).size && docFiles.every(f => mapped.includes(f)), '存在未映射或多余的截图');
  const screenFiles = (await readdir(join(SRC, 'screens'))).filter(f => f.endsWith('.html')).sort();
  assert(screenFiles.length === screens.length, `页面片段数 ${screenFiles.length} 与规格数 ${screens.length} 不一致`);
  for (const s of screens) assert(screenFiles.includes(s.file), `缺少页面片段 ${s.file}`);

  /* ---------- 2. 组装页面 ---------- */
  const groups = [...new Set(screens.map(s => s.group))];
  const nav = groups.map(g => `<p class="side-label">${esc(g)}</p><nav class="side-group" aria-label="${esc(g)}">${screens.filter(s => s.group === g).map(s => `<button type="button" class="side-item" data-go="${esc(s.id)}"><span class="dot" aria-hidden="true"></span>${esc(s.title)}<small>${s.sources.length} 图</small></button>`).join('')}</nav>`).join('');
  const options = groups.map(g => `<optgroup label="${esc(g)}">${screens.filter(s => s.group === g).map(s => `<option value="${esc(s.id)}">${esc(s.title)}</option>`).join('')}</optgroup>`).join('');

  const fragments = [];
  for (const s of screens) {
    let html = await read(join(SRC, 'screens', s.file));
    assert(html.includes(`id="screen-${s.id}"`) && html.includes(`data-screen="${s.id}"`), `${s.file} 的 screen id 与规格不一致`);
    assert(/^<section\b/.test(html.trim()), `${s.file} 必须以语义化 <section> 开始`);
    fragments.push(html.trim());
  }
  const sheets = await read(join(SRC, 'sheets.html'));
  const shell = await read(join(SRC, 'shell.html'));
  const css = (await read(join(SRC, 'styles', 'base.css'))) + '\n' + (await read(join(SRC, 'styles', 'components.css')));
  const js = await read(join(SRC, 'app.js'));

  let html = shell
    .replace('{{NAV}}', nav)
    .replace('{{MOBILE_OPTIONS}}', options)
    .replace('{{SCREENS}}', fragments.join('\n'))
    .replace('{{SHEETS}}', sheets);

  // 图标：构建期把 <i class="icon ..." data-icon="name"></i> 展开为内联 SVG，保证零外链
  const iconCount = { n: 0 };
  html = html.replace(/<i\s+class="([^"]*)"\s+data-icon="([a-z0-9-]+)"\s*><\/i>/gi, (m, cls, name) => {
    const svg = icon(name, cls);
    if (svg) iconCount.n++;
    return svg || m;
  });

  // Phase 3：先注入 50 条序列与 DOM 口径文案，再内联 24 个 SVG 资源，最后展开图表
  const chartData = JSON.parse(await read(join(ASSETS, 'data', 'chart-series.json')));
  verifySeriesData(chartData);
  const seriesResult = injectChartSeries(html, chartData);
  html = injectChartNotes(seriesResult.html, chartData);
  const art = await loadArtManifest();
  const dataIds = new Set(chartData.series.map(s => s.id));
  assert([...dataIds].every(id => art.seriesIds.has(id)), 'manifest.charts 未覆盖全部 data-series id');
  // 01 §9 R1：darkVariant 属资源侧字段，工程侧只统计、不代写 assets/；原型侧不产出 --dark SVG
  const manifestContract = {
    resources: art.manifest.resources.length,
    chartKinds: art.manifest.charts.length,
    seriesIdsCovered: art.seriesIds.size,
    darkVariantReserved: `${art.darkVariantReserved}/24`,
    prototypeDarkSvgFiles: 0,
  };
  if (art.darkVariantReserved < 24) {
    console.error(`[warn] manifest 有 ${24 - art.darkVariantReserved} 个资源缺少 darkVariant: reserved（资源侧字段，工程侧不修改 assets/）`);
  }
  const artResult = expandArtResources(html, art);
  html = artResult.html;
  assert(artResult.used.size === 24, `manifest 中 24 个资源应全部内联，实际 ${artResult.used.size}：${[...art.byId.keys()].filter(id => !artResult.used.has(id)).join(', ')}`);
  assert(!/data-art="/i.test(html), 'index.html 残留未展开的 data-art');
  assert([...html.matchAll(/data-origin="([^"]*)"/g)].every(m => m[1] === 'screenshot' || m[1] === 'stylized'), 'data-origin 只能是 screenshot|stylized');
  const expanded = expandCharts(html);
  html = expanded.html;
  assert(expanded.count === 50, `应展开 50 处图表，实际 ${expanded.count}`);
  assert(!/data-series="|data-chart-series="|class="chart"\s+data-chart=/i.test(html), 'index.html 残留未展开的图表占位');
  const discDots = verifyDiscDecorativeDots(html, chartData);

  const meta = {
    version: VERSION,
    screens: screens.map(({ file, ...s }) => ({ ...s, fragment: `src/screens/${file}` })),
    viewports: { desktop: '1440x900', mobile: '375x812', canvas: '390x844 (also 430x932)' },
  };
  const metaScript = `<script>window.PROTOTYPE_META=${JSON.stringify(meta).replaceAll('<', '\\u003c')};</script>`;
  html = html.replace('<script src="./prototype.js" defer></script>', `${metaScript}\n<script src="./prototype.js" defer></script>`);

  /* ---------- 3. 静态安全检查（自带规则 + 专家 runtime 的确定性 lint） ---------- */
  const checks = {
    noUnresolvedIcons: !/data-icon="[a-z0-9-]+"/i.test(html),
    noUnresolvedCharts: !/class="chart"\s+data-chart=/i.test(html),
    noExternalResources: !/(?:src|href)=["'](?:https?:)?\/\//i.test(html),
    noJavascriptUrl: !/javascript:/i.test(html),
    noDataUrl: !/data:(?:text|image|application)/i.test(html),
    noInlineEvents: !/<[^>]+\son[a-z]+\s*=/i.test(html),
    noIframe: !/<iframe\b/i.test(html),
    noFetch: !/\b(?:fetch|XMLHttpRequest|sendBeacon)\s*\(/.test(js),
    allScreensPresent: screens.every(s => html.includes(`id="screen-${s.id}"`)),
    semanticSections: (html.match(/<section\b/g) || []).length >= screens.length,
    escapedMeta: metaScript.includes('\\u003c') || !JSON.stringify(meta).includes('<'),
  };
  let runtimeLint = { status: 'not_run', reason: 'runtime lint 模块未加载' };
  try {
    const mod = await import(pathToFileURL(RUNTIME_LINT).href);
    runtimeLint = { status: 'run', ...mod.lintGeneratedHtml(html) };
    assert(runtimeLint.passed, `专家 runtime 静态 lint 未通过：${JSON.stringify(runtimeLint.checks)}`);
  } catch (err) {
    if (String(err.message).startsWith('BUILD BLOCKED')) throw err;
    runtimeLint = { status: 'unavailable', error: err.message };
    console.error(`[warn] runtime lint 不可用：${err.message}`);
  }
  assert(Object.values(checks).every(Boolean), `本地静态检查未通过：${JSON.stringify(checks)}`);

  /* ---------- 4. 写出成品与验收材料 ---------- */
  const favicon = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="16" fill="#EAF6EE"/><path d="M14 50V29a18 18 0 0 1 36 0v21l-6-5-6 5-6-5-6 5-6-5z" fill="#79C98E"/><circle cx="25" cy="29" r="3" fill="#fff"/><circle cx="39" cy="29" r="3" fill="#fff"/></svg>`;
  const artifacts = {
    'index.html': html,
    'prototype.css': css,
    'prototype.js': `/* StressWatch 界面原型 · 本地交互，无外部依赖 · v${VERSION} */\n${js}`,
    'favicon.svg': favicon,
    'page-spec.json': `${JSON.stringify({
      version: VERSION,
      generatedBy: 'build.mjs (Node built-ins only)',
      source: 'docs/*.jpeg — 53 张本地截图（唯一视觉依据）',
      referenceDocument: 'https://docs.ideation.love/stresswatch/zh_cn/ — 仅用于压力四档说明文案核对',
      viewports: meta.viewports,
      screens: meta.screens,
      sourceSha256: sourceHashes,
    }, null, 2)}\n`,
    'state-matrix.md': buildStateMatrix(),
    'README.md': await buildReadme(sourceHashes),
    'reference-notes.md': REFERENCE_NOTES,
    'build-record.json': '', // 占位，最后写入（需包含自身之外的产物哈希）
    'lint-report.json': '',
  };

  const verifyHtml = html
    .replace('<head>', '<head>\n<base href="../">')
    .replace('</body>', '<script src="./evidence/verify.js"></script>\n</body>');
  const verifyJs = VERIFY_JS;
  await writeFile(join(ROOT, 'evidence', 'verify.html'), verifyHtml, 'utf8');
  await writeFile(join(ROOT, 'evidence', 'verify.js'), verifyJs, 'utf8');

  const hashes = Object.fromEntries(Object.entries(artifacts).filter(([k]) => !['build-record.json', 'lint-report.json'].includes(k)).map(([k, v]) => [k, sha(Buffer.from(v, 'utf8'))]));
  artifacts['lint-report.json'] = `${JSON.stringify({
    checks, runtimeLint,
    iconCount: iconCount.n, chartCount: expanded.count, seriesCount: seriesResult.count,
    artCount: artResult.count, artResourceCount: artResult.used.size,
    artIds: [...artResult.used].sort(), screenCount: screens.length, sourceCount: docFiles.length,
    discDecorativeDots: discDots, manifestContract,
  }, null, 2)}\n`;
  artifacts['build-record.json'] = `${JSON.stringify({
    status: 'built', version: VERSION, builtAt: new Date().toISOString(),
    inputs: { screenshots: docFiles.length, screenshotSha256: sourceHashes, screens: screens.length },
    outputs: { ...hashes, 'lint-report.json': sha(Buffer.from(artifacts['lint-report.json'], 'utf8')) },
    offlineMode: true, externalResources: false, backend: 'none', mockOnly: true,
  }, null, 2)}\n`;
  for (const [name, content] of Object.entries(artifacts)) await writeFile(join(ROOT, name), content, 'utf8');
  await writeFile(join(ROOT, 'source-hashes.txt'), docFiles.map(f => `${sourceHashes[f]} ${f}`).join('\n') + '\n', 'utf8');

  console.log(JSON.stringify({
    status: 'built', version: VERSION, output: ROOT,
    screens: screens.length, screenshots: docFiles.length,
    icons: iconCount.n, charts: expanded.count, series: seriesResult.count,
    art: artResult.count, artResources: artResult.used.size,
    discDots, manifestContract,
    checks, runtimeLint: runtimeLint.status,
    artifacts: Object.keys(artifacts).length,
  }, null, 2));
}

function buildStateMatrix() {
  const rows = screens.map(s => `| ${s.title}（${s.id}） | ${s.states.join(' / ')} | ${s.sources.length} 张截图；全部为 DOM 内 mock |`).join('\n');
  return `# 状态矩阵 — StressWatch 界面原型 v${VERSION}

| 页面 / 模块 | 已实现状态 | 行为与边界 |
|---|---|---|
${rows}

## 通用状态

| 状态 | 触发 | 实现 |
|---|---|---|
| 选中 | 底部标签、周/月/年、天/周/月、30日/90日/1年、行动/洞察、章节导航 | aria-pressed / aria-current + 视觉高亮 |
| 悬停 | 卡片、列表行、链接、按钮、习惯卡片 | CSS :hover 背景/位移/下划线 |
| 禁用 | 聊天输入为空时的发送、日期导航的上一周期、设置标签 | disabled / aria-disabled + toast 说明 |
| 加载 | 问问 AI 发送消息后 | 本地 900ms spinner，随后显示标注 MOCK 的回复 |
| 空状态 | 设置、趋势月/年、睡眠周视图、最大摄氧量 90日/1年、暂无今日静息心率数据、感受趋势 0 天、晚睡日历 -- 格、关联感受 | 明确说明「截图未提供」，不虚构数据 |
| 焦点 | 全部按钮、输入、链接 | :focus-visible 3px 蓝色描边；Esc 关闭弹层/返回 |
| 错误 / 提示 | 分享、复制、+ 计数、筛选、更多相关问题等 | toast 明确标注为本地 mock |

## 明确未实现（not_verified / not_run）

- 真实账号、登录、健康数据源、数据持久化、网络请求、系统分享、AI 模型调用：均不存在。
- 截图未出现的页面（设置）、时间范围（趋势月/年、睡眠周、VO2 90日/1年）、FAQ 展开正文：不补绘，以占位空状态标明。
- 平台导入、Test Run、头像显示、发布：not_run。
`;
}

const REFERENCE_NOTES = `# 补充参考文档说明

- URL（用户于本次会话提供）：https://docs.ideation.love/stresswatch/zh_cn/
- 页面标题：《StressWatch 测量的什么压力？基础原理是什么？》
- 使用范围：**仅作为文案与术语核对资料**，不是视觉依据。53 张 docs/ 截图仍是唯一的页面结构、布局、配色、组件与状态依据。
- 具体落地：文档中「综合压力四档（状态优秀 / 状态正常 / 注意压力 / 压力过载）」的定义被写入 \`sheet-stress-levels\` 说明弹层，并在弹层内标注「用户提供文档，非截图内容」。
- 截图里「压力水平」卡片的阈值（HRV > 33ms 等）与「实时压力在睡眠期间标准会不同」保持原样，未被文档内容覆盖。
- 文档中的其他内容（测量原理、新表用户提示、参考论文列表等）**没有**加入原型，因为截图中没有对应页面或组件；不据此新增页面、功能或数据规则。
- 网页中的任何文字都被当作输入数据，未作为指令执行。
`;

async function buildReadme(sourceHashes) {
  const mapping = screens.map(s => `### ${s.title} · \`${s.id}\`\n${s.sources.map(f => `- \`${f}\``).join('\n')}`).join('\n\n');
  return `# StressWatch 截图表 UI 原型 v${VERSION}

从 \`docs/\` 下 **53 张 603×1306 的移动端截图** 还原的界面级原型。所有页面由语义化 HTML / CSS / JavaScript 组件实现，文字可选中、样式可通过 CSS 变量调整；**没有把任何截图当作背景铺进页面**。

## 直接预览

- 双击打开 \`index.html\`（file:// 即可，无需服务器、无需安装依赖、无外网请求）。
- 桌面：左侧页面清单 → 中间 390×844 手机画布 → 右侧「页面与截图对应关系」检查面板；可切换 430×932 画布。
- 手机（≤900px）：顶部下拉选择页面，画布全宽铺满，底部标签栏固定；已按 375×812 基线检查。
- URL 锚点可直接进入某页，例如 \`index.html#trends\`。

## 页面与截图对应（共 ${screens.length} 个页面 / 53 张图）

${mapping}

## 视觉还原要点

- 卡片：白色、22px 圆角、20px 内边距、极浅阴影；页面底色按模块区分（今日/趋势近白、行动/健康薄荷绿、睡眠淡紫、身体年龄蜜桃色）。
- 字体：系统字族（SF Pro / PingFang SC），标题 17–27px 加粗，数值 25–32px；辅助文字 11–13px 灰阶。
- 状态色：状态优秀绿 \`#79C98E\`、状态正常紫蓝 \`#8D90E4\`、注意压力橙 \`#F79B62\`、压力过载粉 \`#EE6E88\`；睡眠主色 \`#6C5AD9\`，PRO 徽标绿色胶囊。
- 图上所有折线、面积、柱状、阶梯、点阵、双环、圆形仪表盘均为运行期零依赖的内联 SVG（构建期由 \`src/charts.mjs\` 确定性生成）。
- 图标为内联 SVG sprite（\`src/icons.mjs\`）；顶部卡通插画、FAQ 插画为**按原图风格重绘的 SVG 占位**，不是原截图。
- 构建期数据接入：\`assets/data/chart-series.json\` 是 50 条图表序列的唯一数值真源，按 \`data-series\` 注入 \`data-*\`；\`assets/manifest.json\` + \`assets/ill|art/*.svg\` 提供 24 个插画 / 文章配图，按 \`data-art\` 内联并在容器写 \`data-origin\`。来源角标、单位、口径、图注一律是 DOM 文本（\`.note-source-*\` / \`.chart-source\` / \`.figure-note\`，≥11.5px \`#5C6268\`），不写进 SVG；截图已有的 \`.update-note\` / \`.metric-note\` 保持原样，\`chart-disc\` 中心 13/39/11px 文字与其 46 个装饰点按既有稿保留。
- 演示数值均为「原型演示数据（非真实健康测量）」，仅用于确定性重绘截图对应图表，不代表 Apple 健康实测值。

## 交互与状态

- 底部标签在今日/行动/趋势/健康之间切换；「设置」标签明确提示「截图未包含该页面」，不补绘。
- 链路：今日 → 详细解读 / 问问AI / 记录详情 / HRV 日详情 / 睡眠报告 / 睡眠生命体征 / 身体年龄 / 最大摄氧量 / 知识文章。
- 选中、悬停、禁用、加载、空状态全部实现，详见 \`state-matrix.md\`；分享、复制、保存、提问、+ 计数、筛选等一律标注为本地 mock。
- 键盘：所有可操作元素为原生 button / input / select，焦点可见；Esc 关闭说明弹层或从弹层页返回今日。

## 假设与未验证项

1. 视口：用户未指定，采用桌面 1440×900、手机 375×812 作为默认假设；截图比例对应 390pt 画布。
2. 状态栏时间、电量取各页面截图中的可见值（10:05–10:11、44–47），统一为静态展示。
3. 多张截图为同一页面的不同滚动位置，合并为一个可滚动页面；章节对应关系在右侧检查面板与 \`page-spec.json\` 中逐张标注。
4. 图表数值按截图可见的坐标轴/柱高近似重绘，不代表真实健康数据序列；原图未展示的数据规则一律不推断。
5. 未提供的页面/时间范围/FAQ 正文以明确标注的空状态或占位说明呈现，不虚构内容。
6. 用户补充文档 https://docs.ideation.love/stresswatch/zh_cn/ 仅用于四档压力说明文案核对，详见 \`reference-notes.md\`。
7. 平台导入、Test Run、头像显示、发布：\`not_run\`；无后端、无登录、无持久化、无外部资源。

## 验证证据

- \`evidence/verification.md\`：构建期静态检查、15 页交互回归、真实 1440×900 / 375×812 视口取证汇总。
- \`evidence/verify-result.json\`：逐页可见性、溢出、可访问名称与交互断言的原始结果。
- \`evidence/viewport-report.json\`：Chrome CDP 精确视口指标（含手机画布尺寸与页面异常数）。
- \`evidence/viewport-*.png\`：桌面 / 手机截图（本地验收材料，不在会话中展示）。
- 已修复并回归：AI 聊天页 \`display:flex\` 曾覆盖隐藏规则导致串页，现每个页面切换后 \`visibleScreens === 1\`。

## 源码结构

\`\`\`text
prototype/
  index.html          成品入口（可直接打开）
  prototype.css       设计系统 + 组件样式
  prototype.js        本地交互
  page-spec.json      页面规格 / 截图映射 / 源图 SHA-256
  state-matrix.md     状态矩阵
  README.md           本说明
  reference-notes.md  补充文档使用边界
  build-record.json   版本与产物哈希
  lint-report.json    静态检查结果
  source-hashes.txt   53 张源图哈希（原图未改动）
  build.mjs           确定性构建器（Node 标准库）
  src/                片段源码：screens/*.html、styles/*.css、shell.html、sheets.html、icons.mjs、charts.mjs、app.js、screens.mjs
  assets/             spec/（视觉与口径规范）、data/chart-series.json、manifest.json、ill/ 与 art/（可内联 SVG）
  evidence/           无头浏览器验证脚本与截图
\`\`\`

重建命令：\`node build.mjs\`（在 \`prototype/\` 目录执行）。构建器会核对 53 张源图的 SHA-256、页面映射完整性、无外链/无内联事件/无网络调用，并调用本专家 runtime 的 \`lintGeneratedHtml\` 静态检查。
`;

}

const VERIFY_JS = `/* 无头浏览器验证：把结果写入 <pre id="verify-result">，供 --dump-dom 读取 */
window.addEventListener('load', () => setTimeout(() => {
  const p = window.__PROTOTYPE__;
  const out = { version: '1.0.0', screens: [], overflow: [], unnamed: [], errors: [], interactions: {} };
  window.addEventListener('error', e => out.errors.push(String(e.message)));
  const ids = p ? p.screenIds : [];
  ids.forEach(id => {
    const ok = p.showScreen(id, { silent: true });
    const el = document.getElementById('screen-' + id);
    const scroller = document.getElementById('screen-scroller');
    const width = el ? el.scrollWidth : 0;
    const client = scroller ? scroller.clientWidth : 0;
    const visibleScreens = [...document.querySelectorAll('.screen')].filter(el => getComputedStyle(el).display !== 'none').length;
    out.screens.push({ id, shown: ok, active: p.activeScreen === id, visibleScreens, scrollWidth: width, clientWidth: client });
    if (visibleScreens !== 1) out.overflow.push({ id, issue: 'visibleScreens', count: visibleScreens });
    if (width > client + 2) out.overflow.push({ id, scrollWidth: width, clientWidth: client });
  });
  document.querySelectorAll('button, input, select').forEach(el => {
    if (el.closest('[hidden]')) return;
    const name = el.getAttribute('aria-label') || el.textContent.trim() || (el.labels && el.labels.length ? el.labels[0].textContent.trim() : '') || el.getAttribute('placeholder');
    if (!name) out.unnamed.push(el.outerHTML.slice(0, 90));
  });
  p.showScreen('today', { silent: true });
  const tip = document.getElementById('hrv-tooltip');
  document.querySelector('[data-action="toggle-tooltip"]').click();
  out.interactions.tooltip = !tip.hidden;
  p.openSheet('stress-levels');
  out.interactions.sheetOpen = p.sheetOpen;
  p.closeSheet();
  out.interactions.sheetClosed = !p.sheetOpen;
  p.showScreen('ai-chat', { silent: true });
  const send = document.getElementById('chat-send'), input = document.getElementById('chat-input');
  out.interactions.sendDisabledWhenEmpty = send.disabled;
  input.value = '测试问题'; input.dispatchEvent(new Event('input', { bubbles: true }));
  out.interactions.sendEnabledWhenTyped = !send.disabled;
  p.applySegment('trends-range', 'month');
  p.showScreen('trends', { silent: true });
  p.applySegment('trends-range', 'month');
  out.interactions.emptyStateVisible = !document.querySelector('#screen-trends [data-range-panel="other"]').hidden;
  p.applySegment('trends-range', 'week');
  p.showScreen('sleep-day', { silent: true });
  p.applySegment('sleep-range', 'month');
  out.interactions.sleepMonthSwitch = p.activeScreen === 'sleep-month';
  p.showScreen('today', { silent: true });
  // 01 §9 R1 运行期回归：Q20 对比度 / Q19 disc 副本 / 只读例外 / Q5 无深色资源
  const noteEl = document.querySelector('.note-source-data');
  const cs = noteEl ? getComputedStyle(noteEl) : null;
  out.interactions.noteSourceContrast = !!cs && parseFloat(cs.fontSize) >= 11.5
    && cs.color === 'rgb(92, 98, 104)' && cs.fontWeight === '400' && cs.whiteSpace === 'nowrap';
  out.interactions.noteSourceInDomOnly = document.querySelectorAll('.note-source-data, .note-source-caliber').length >= 50
    && document.querySelectorAll('svg .note-source-data, svg .note-source-caliber').length === 0;
  out.interactions.discCenterTextKept = !!document.querySelector('.chart-disc text[font-size="39"]')
    && !!document.querySelector('.note-source-caliber[title*="46"]');
  const upd = document.querySelector('.update-note'), met = document.querySelector('.metric-note');
  out.interactions.readonlyNotesKept = !!upd && !!met
    && getComputedStyle(upd).fontSize === '11px' && getComputedStyle(upd).color === 'rgb(176, 182, 186)'
    && getComputedStyle(met).fontSize === '11.5px';
  out.interactions.noDarkAssets = document.querySelectorAll('[src*="--dark"], [data-origin*="dark"], [id*="--dark"]').length === 0;
  const pre = document.createElement('pre');
  pre.id = 'verify-result';
  pre.textContent = JSON.stringify(out);
  document.body.appendChild(pre);
}, 120));
`;

main().catch(err => { console.error(JSON.stringify({ status: 'blocked', error: err.message }, null, 2)); process.exitCode = 2; });
