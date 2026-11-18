// 确定性 SVG 图表组件：构建期把 <div class="chart" data-chart="..."> 展开为内联 SVG。
// 本模块只负责「渲染」：所有数值/颜色序列由 build.mjs 从 assets/data/chart-series.json
// 注入到 data-* 属性（唯一数值真源），此处不再内置任何业务数据，也不再用 data-seed
// 生成测量类图形；唯一例外是 disc 的 46 个纯装饰彩点（rng(5)，无数据语义）。
// 所有数值均来自 data-* 属性并经过 Number()/白名单校验，运行期无网络、无脚本注入。
// 01 §1.5 / §9 R1 命名消歧：只改局部名，色值一律保持（旧名 greenDark / purpleSoft / ink）。
// 与 components.css 的同名 token 逐字同值：--chart-line-green / --chart-baseline-lav / --chart-ink。
// 不与 base.css 的 --green-deep #4EA974 / --purple-soft #EDE8FC / --ink #292C30 合并。
const C = {
  green: '#79C98E', chartLineGreen: '#4FA976', lavender: '#8D90E4', purple: '#6C5AD9',
  chartBaselineLav: '#A9A4F0', orange: '#F79B62', pink: '#EE6E88', teal: '#7BD3C4',
  sky: '#57BFE6', red: '#F0677E', gray: '#C9CDD2', grayLine: '#E4E7E9',
  chartInk: '#2C2F33', faint: '#F0F1F3', white: '#FFFFFF',
  // 图表专用中性 token（01 §1.5 / §4.4）：缺失值空点
  emptyDot: '#E9EAEE',
};
const color = (name) => C[name] || (/^#[0-9a-fA-F]{3,8}$/.test(String(name)) ? name : C.gray);
// nums() 只接受有限数字：build.mjs 已把 JSON 的 null 转成 0（并置 data-colors=faint），
// 绝不把文本 "null" 传进来，否则会被过滤并造成点数错位。
const nums = (raw, fallback = []) => {
  const out = String(raw || '').split(',').map(v => Number(v.trim())).filter(Number.isFinite);
  return out.length ? out : fallback;
};
const list = (raw, sep = '|') => String(raw || '').split(sep).map(s => s.trim());
const seg = (raw) => list(raw).map(item => {
  const [w, c] = item.split(':');
  return { w: Math.max(0, Math.min(100, Number(w) || 0)), c: color(c || 'grayLine') };
});
const esc = (s) => String(s).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const num = (v, d) => Number.isFinite(Number(v)) ? Number(v) : d;
let uid = 0;
const nextId = () => `sw-c${++uid}`;

// 仅保留给 chart-disc 的 46 个纯装饰彩点（无测量语义，见 02 §5.3 ⑤）
function rng(seed) {
  let a = (Number(seed) || 1) >>> 0;
  return () => { a |= 0; a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
function frame(h, inner, aria) {
  return `<svg class="chart-svg" viewBox="0 0 320 ${h}" role="img" aria-label="${esc(aria)}" xmlns="http://www.w3.org/2000/svg">${inner}</svg>`;
}
const hline = (y, from = 8, to = 312, dash = '3 4') => `<line x1="${from}" y1="${y}" x2="${to}" y2="${y}" stroke="${C.grayLine}" stroke-width="1" stroke-dasharray="${dash}" vector-effect="non-scaling-stroke"/>`;
const vline = (x, y0, y1) => `<line x1="${x}" y1="${y0}" x2="${x}" y2="${y1}" stroke="${C.grayLine}" stroke-width="1" stroke-dasharray="3 4" vector-effect="non-scaling-stroke"/>`;
const label = (x, y, text, opts = '') => `<text x="${x}" y="${y}" font-size="8.5" fill="#9BA1A7" font-family="-apple-system,BlinkMacSystemFont,PingFang SC,sans-serif" ${opts}>${esc(text)}</text>`;
const dot = (x, y, r, fill, stroke = C.white) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}" stroke="${stroke}" stroke-width="2"/>`;
const poly = (pts, stroke, width = 1.6, dash = '') => `<polyline points="${pts.map(p => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ')}" fill="none" stroke="${stroke}" stroke-width="${width}" stroke-linejoin="round" stroke-linecap="round" ${dash ? `stroke-dasharray="${dash}"` : ''} vector-effect="non-scaling-stroke"/>`;
// 缺失值空点：柱高 0 / 点 #E9EAEE（01 §4.4）；faint 由 data-colors 指定
const isMissing = (c) => String(c || '').trim() === 'faint';
// 实时压力柱色：1–20 绿 / 21–60 紫 / 61–80 橙 / 81–100 粉（02 §5.4）
const histColor = (v) => v <= 20 ? C.green : v <= 60 ? C.lavender : v <= 80 ? C.orange : C.pink;

/** 折线图：可含虚线网格、每点独立状态色、基准线与 x 轴标签。支持 data-min/data-max。 */
function line(a) {
  const h = 132, top = 14, bottom = 104;
  const vals = nums(a.values, [0, 0]);
  const max = num(a.max, 100), min = num(a.min, 0);
  const colors = list(a.colors, ',');
  const labels = list(a.labels);
  const pts = vals.map((v, i) => [18 + i * (284 / Math.max(1, vals.length - 1)), bottom - ((v - min) / (max - min || 1)) * (bottom - top)]);
  let s = '';
  for (let i = 0; i <= 3; i++) s += hline(top + i * ((bottom - top) / 3));
  if (a.grid !== 'none') s += `${vline(18, top, bottom)}${vline(160, top, bottom)}${vline(302, top, bottom)}`;
  if (a.baseline) {
    const by = bottom - ((Number(a.baseline) - min) / (max - min || 1)) * (bottom - top);
    s += `<line x1="8" y1="${by}" x2="312" y2="${by}" stroke="${color(a['baseline-color'] || 'chartBaselineLav')}" stroke-width="1.4" stroke-dasharray="2 3" vector-effect="non-scaling-stroke"/>`;
  }
  // 缺失点不参与连线（避免把 0 画成真实测量值），只画 #E9EAEE 空点
  const connected = pts.filter((_, i) => !isMissing(colors[i]));
  s += poly(connected.length > 1 ? connected : pts, color(a.stroke || '#B9BEC6'), 1.6);
  pts.forEach((p, i) => {
    s += isMissing(colors[i]) ? dot(p[0], p[1], 4.6, C.emptyDot) : dot(p[0], p[1], 4.6, color(colors[i] || 'green'));
  });
  if (labels.length) {
    const steps = labels.length - 1 || 1;
    labels.forEach((t, i) => { s += label(18 + i * (284 / steps), 122, t, i === 0 ? 'text-anchor="start"' : i === labels.length - 1 ? 'text-anchor="end"' : 'text-anchor="middle"'); });
  }
  return frame(h, s, a.aria || '折线趋势图');
}

/** 面积图：带渐变填充与可选基准灰线（身体年龄 / 衰老速度）。 */
function area(a) {
  const h = 128, top = 16, bottom = 106;
  const vals = nums(a.values, [0, 0]);
  const max = num(a.max, 41), min = num(a.min, 20);
  const main = color(a.fill || 'green'), stroke = color(a.line || 'chartLineGreen');
  const id = nextId();
  const pts = vals.map((v, i) => [10 + i * (300 / (vals.length - 1)), bottom - ((v - min) / (max - min || 1)) * (bottom - top)]);
  let s = `<defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${main}" stop-opacity=".34"/><stop offset="1" stop-color="${main}" stop-opacity=".02"/></linearGradient></defs>`;
  for (let i = 0; i <= 3; i++) s += hline(top + i * ((bottom - top) / 3));
  s += `<path d="M${pts[0][0]},${bottom} ${pts.map(p => `L${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ')} L${pts.at(-1)[0]},${bottom} Z" fill="url(#${id})"/>`;
  s += poly(pts, stroke, 1.8);
  if (a.baseline) {
    const by = bottom - ((Number(a.baseline) - min) / (max - min || 1)) * (bottom - top);
    s += poly([[10, by], [310, by]], '#8C9298', 1.2);
  }
  list(a.ylabels).forEach((t, i, all) => label(315, top + i * ((bottom - top) / Math.max(1, all.length - 1)) + 3, t, 'text-anchor="end"'));
  list(a.labels).forEach((t, i, all) => label(10 + i * (300 / Math.max(1, all.length - 1)), 122, t, i === 0 ? 'text-anchor="start"' : i === all.length - 1 ? 'text-anchor="end"' : 'text-anchor="middle"'));
  return frame(h, s, a.aria || '面积趋势图');
}

/** 柱状图：可指定逐柱颜色、平均线、y 轴刻度与双行标签。faint=无数据（柱高 0）。 */
function bars(a) {
  const h = num(a.height, 148), top = 14, bottom = h - 32;
  const vals = nums(a.values, [0]);
  const colors = list(a.colors, ',');
  const labels = list(a.labels);
  const max = num(a.max, 100);
  const slot = 300 / vals.length, bw = Math.min(num(a.barwidth, 15), slot - 5);
  let s = '';
  for (let i = 0; i <= 3; i++) s += hline(top + i * ((bottom - top) / 3));
  if (a.avg) {
    const ay = bottom - (Number(a.avg) / max) * (bottom - top);
    s += `<line x1="8" y1="${ay}" x2="312" y2="${ay}" stroke="${color(a['avg-color'] || 'lavender')}" stroke-width="1.3" vector-effect="non-scaling-stroke"/>`;
  }
  vals.forEach((v, i) => {
    const bh = isMissing(colors[i]) ? 0 : Math.max(0, (v / max) * (bottom - top));
    const x = 10 + slot * i + (slot - bw) / 2;
    if (bh > 0) s += `<rect x="${x.toFixed(1)}" y="${(bottom - bh).toFixed(1)}" width="${bw}" height="${bh.toFixed(1)}" rx="${Math.min(bw / 2, 5)}" fill="${color(colors[i] || 'lavender')}" ${a.roundtop === 'dot' ? '' : ''}/>`;
    if (a.roundtop === 'dot' && bh > 0) s += dot(x + bw / 2, bottom - bh, 5, C.white, color(colors[i] || 'green'));
  });
  list(a.ylabels).forEach((t, i, all) => label(315, top + i * ((bottom - top) / Math.max(1, all.length - 1)) + 3, t, 'text-anchor="end"'));
  labels.forEach((t, i) => {
    const parts = t.split('/');
    const x = 10 + slot * i + slot / 2;
    s += label(x, bottom + 13, parts[0], 'text-anchor="middle"');
    if (parts[1]) s += label(x, bottom + 23, parts[1], 'text-anchor="middle"');
  });
  return frame(h, s, a.aria || '柱状统计图');
}

/** 实时压力直方图：74 个显式值（data-values），柱色按数值阈值；紫色带为睡眠时段示意。 */
function hist(a) {
  const h = 132, bottom = 104, top = 20;
  const vals = nums(a.values, []);
  const n = 74; // 02 §5.4：每柱 = 1 次实时压力采样，共 74 次
  let s = '';
  for (let i = 0; i <= 3; i++) s += hline(top + i * ((bottom - top) / 3));
  s += `<rect x="96" y="${top}" width="108" height="${bottom - top}" fill="#EDE8FC" opacity=".66"/>`;
  s += `<rect x="96" y="${top}" width="108" height="2.5" fill="${C.purple}"/>`;
  vals.forEach((v, i) => {
    if (i >= n) return;
    const x = 18 + i * (284 / n);
    const bh = Math.max(0, (v / 100) * (bottom - top));
    s += `<rect x="${x.toFixed(1)}" y="${(bottom - bh).toFixed(1)}" width="2.5" height="${bh.toFixed(1)}" fill="${histColor(v)}" opacity=".85"/>`;
  });
  s += `<path d="M266 ${top + 3}h10v-4h-10z" fill="${C.purple}"/>`;
  [0, 1, 2, 3].forEach((i, k) => label(314, top + k * ((bottom - top) / 3) + 3, [100, 50, 0, ''][k], 'text-anchor="end"'));
  ['00:00', '06:00', '12:00'].forEach((t, i) => label(18 + i * 142, 121, t, i === 0 ? 'text-anchor="start"' : i === 2 ? 'text-anchor="end"' : 'text-anchor="middle"'));
  return frame(h, s, a.aria || '实时压力柱状直方图');
}

/** 睡眠阶段阶梯图：段值来自 data-segments（startPct:widthPct:level:kind）。 */
function step(a) {
  const h = 130, top = 18, bottom = 100;
  const colors = { wake: C.orange, rem: C.teal, core: C.lavender, deep: C.purple };
  const segments = list(a.segments).map(item => {
    const [x, w, level, kind] = item.split(':');
    return { x: Number(x), w: Number(w), level: Number(level), c: colors[kind] || C.lavender };
  });
  let s = `${hline(top)}${hline((top + bottom) / 2)}${hline(bottom)}`;
  segments.forEach(g => {
    const x = 14 + (g.x / 100) * 292, w = (g.w / 100) * 292;
    const y = bottom - (g.level / 100) * (bottom - top) * 0.85;
    s += `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${Math.max(1, w).toFixed(1)}" height="${(bottom - y).toFixed(1)}" fill="${g.c}" opacity=".92"/>`;
  });
  ['02:47', '05:15', '07:42'].forEach((t, i) => label(14 + i * 146, 120, t, i === 0 ? 'text-anchor="start"' : i === 2 ? 'text-anchor="end"' : 'text-anchor="middle"'));
  return frame(h, s, a.aria || '睡眠阶段分布图');
}

/** 7 行 × 24 列压力时段点阵：data-matrix 为显式编码矩阵（0 空点 / 1–4 四档状态色）。 */
function dots(a) {
  const rows = num(a.rows, 7), cols = num(a.cols, 24), h = 116;
  const matrix = String(a.matrix || '').split('|').map(row => row.split(',').map(v => Number(v.trim())));
  const palette = [C.green, C.lavender, C.orange, C.pink];
  let s = '';
  for (let i = 0; i < cols; i += 3) label(14 + i * (292 / cols), 10, String(i), 'text-anchor="middle"');
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const code = Number(matrix[y] && matrix[y][x]) || 0;
      const fill = code >= 1 && code <= 4 ? palette[code - 1] : C.emptyDot;
      s += `<circle cx="${(14 + x * (292 / cols)).toFixed(1)}" cy="${(22 + y * 13).toFixed(1)}" r="3.1" fill="${fill}"/>`;
    }
  }
  return frame(h, s, a.aria || '一周各时段压力状态点阵');
}

/** 睡眠双环：外/内环占比由 data-outer-value / data-inner-value 注入（0.68 / 0.49）。 */
function sleepRing(a) {
  const h = 220, cx = 160, cy = 108;
  const R1 = 78, R2 = 54;
  const c1 = 2 * Math.PI * R1, c2 = 2 * Math.PI * R2;
  const outer = color(a.outer || 'purple'), inner = color(a.inner || 'chartBaselineLav');
  const outerRatio = num(a['outer-value'], 0), innerRatio = num(a['inner-value'], 0);
  let s = `<circle cx="${cx}" cy="${cy}" r="${R1}" fill="none" stroke="#F0EEFC" stroke-width="24"/>`;
  s += `<circle cx="${cx}" cy="${cy}" r="${R1}" fill="none" stroke="${outer}" stroke-width="24" stroke-linecap="round" stroke-dasharray="${(c1 * outerRatio).toFixed(1)} ${c1}" transform="rotate(115 ${cx} ${cy})"/>`;
  s += `<circle cx="${cx}" cy="${cy}" r="${R2}" fill="none" stroke="#F3F1FD" stroke-width="17"/>`;
  s += `<circle cx="${cx}" cy="${cy}" r="${R2}" fill="none" stroke="${inner}" stroke-width="17" stroke-linecap="round" stroke-dasharray="${(c2 * innerRatio).toFixed(1)} ${c2}" transform="rotate(120 ${cx} ${cy})"/>`;
  s += `<circle cx="${cx}" cy="${cy - R1}" r="13" fill="${outer}"/>`;
  s += `<path d="M${cx - 4} ${cy - R1 + 3}a5 5 0 1 0 8-4 6 6 0 1 1-8 4z" fill="#fff"/>`;
  s += `<circle cx="${cx}" cy="${cy - R2}" r="12" fill="${inner}"/>`;
  s += `<path d="M${cx} ${cy - R2 - 6}l2 4 4.4.6-3.2 3 .8 4.4-4-2.2-4 2.2.8-4.4-3.2-3 4.4-.6z" fill="#fff"/>`;
  return frame(h, s, a.aria || '睡眠时长与质量双环图');
}

/** 身体年龄圆形刻度盘：中心 13/39/11px SVG 文字为截图可见既有例外，原样保留（Q19）。
    口径/来源/单位由 DOM 的 .note-source-* 副本承担（唯一口径载体）；
    46 个彩点由 rng(5) 生成，纯装饰、无数据语义，与 sharedSeries.discDecorativeDots.dots 逐点同值，
    不按「L4 ≤6 元素」删减或重排（01 §3.0 R2 补充 / 02 §5.3 ⑤）。 */
function disc(a) {
  const h = 250, cx = 160, cy = 122, R = 96;
  const c = 2 * Math.PI * R;
  let s = `<circle cx="${cx}" cy="${cy}" r="${R}" fill="#FDECE0"/>`;
  s += `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="#8FC9E8" stroke-width="7" stroke-linecap="round" stroke-dasharray="${(c * .31).toFixed(1)} ${c}" transform="rotate(130 ${cx} ${cy})"/>`;
  s += `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="${C.green}" stroke-width="7" stroke-linecap="round" stroke-dasharray="${(c * .55).toFixed(1)} ${c}" transform="rotate(245 ${cx} ${cy})"/>`;
  const r = rng(a.seed || 5); // 仅此处使用 data-seed：46 个装饰点，无测量语义
  for (let i = 0; i < 46; i++) {
    const ang = r() * Math.PI * 2, rad = R + 8 + r() * 20;
    const cols = ['#8FD0E8', '#F7BC9C', '#A8D9B4', '#C9BCEB'];
    s += `<circle cx="${(cx + Math.cos(ang) * rad).toFixed(1)}" cy="${(cy + Math.sin(ang) * rad).toFixed(1)}" r="${(1 + r() * 2).toFixed(1)}" fill="${cols[i % 4]}" opacity=".8"/>`;
  }
  s += `<circle cx="${cx}" cy="${cy}" r="60" fill="#FBF8F5"/>`;
  s += `<text x="${cx}" y="${cy - 14}" text-anchor="middle" font-size="13" font-weight="600" fill="#6A6E72" font-family="-apple-system,PingFang SC,sans-serif">${esc(a.title || '身体年龄')}</text>`;
  s += `<text x="${cx}" y="${cy + 22}" text-anchor="middle" font-size="39" font-weight="700" fill="#25282B" font-family="-apple-system,PingFang SC,sans-serif">${esc(a.value || '34.2')}</text>`;
  s += `<text x="${cx}" y="${cy + 42}" text-anchor="middle" font-size="11" fill="#5D6266" font-family="-apple-system,PingFang SC,sans-serif">${esc(a.note || '多5.9岁')}</text>`;
  return frame(h, s, a.aria || '身体年龄圆形仪表盘');
}

/** 水平堆叠条（恢复性睡眠 / 晚睡分布 / 说明弹层）。 */
function stack(a) {
  const h = 20;
  let x = 0, s = '';
  const parts = seg(a.segments);
  parts.forEach((p, i) => {
    s += `<rect x="${x}" y="2" width="${(p.w * 3.2).toFixed(1)}" height="14" fill="${p.c}" rx="${i === 0 ? 7 : 0}"/>`;
    x += p.w * 3.2;
  });
  s += `<rect x="0" y="2" width="320" height="14" fill="none" stroke="#EEF0F2" stroke-width="0"/>`;
  return frame(h, `<rect x="0" y="2" width="320" height="14" rx="7" fill="#EDEBFA"/>${s}`, a.aria || '分段占比条');
}

/** 垂直胶囊堆叠条（压力分布）。 */
function capsule(a) {
  const h = 190, x = 232, w = 34, top = 14, bottom = 174;
  const parts = seg(a.segments);
  let y = bottom, s = `<rect x="${x}" y="${top}" width="${w}" height="${bottom - top}" rx="17" fill="#EFF0F2"/>`;
  parts.forEach(p => {
    const ph = (p.w / 100) * (bottom - top);
    s += `<rect x="${x}" y="${(y - ph).toFixed(1)}" width="${w}" height="${ph.toFixed(1)}" fill="${p.c}"/>`;
    y -= ph;
  });
  s += `<clipPath id="${nextId()}"><rect x="${x}" y="${top}" width="${w}" height="${bottom - top}" rx="17"/></clipPath>`;
  return frame(h, s, a.aria || '压力分布堆叠条');
}

/** 迷你折线（无坐标轴），用于卡片内的趋势预览。序列由 data-values 注入。 */
function spark(a) {
  const h = 34;
  const vals = nums(a.values, [0, 0]);
  // 序列为真实单位（ms / bpm / kg），按序列自身 min/max 归一化，不能把 min 固定为 0
  const max = Math.max(...vals), min = Math.min(...vals);
  const pts = vals.map((v, i) => [4 + i * (312 / (vals.length - 1)), 27 - ((v - min) / Math.max(1, max - min)) * 22]);
  const col = color(a.color || 'gray');
  let s = '';
  if (a.fill !== 'none') {
    const id = nextId();
    s += `<defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${col}" stop-opacity=".20"/><stop offset="1" stop-color="${col}" stop-opacity="0"/></linearGradient></defs>`;
    s += `<path d="M${pts[0][0]},30 ${pts.map(p => `L${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ')} L${pts.at(-1)[0]},30 Z" fill="url(#${id})"/>`;
  }
  s += poly(pts, col, 1.5);
  if (a.dot !== 'none') s += dot(pts.at(-1)[0], pts.at(-1)[1], 3.4, color(a.dot || 'white'), col);
  return frame(h, s, a.aria || '迷你趋势折线');
}

/** 红色心率波形（带浅红面积与 y 轴刻度）。支持 data-min/data-max。 */
function wave(a) {
  const h = num(a.height, 118), top = 12, bottom = h - 22;
  const vals = nums(a.values, [0, 0]);
  const max = num(a.max, 80), min = num(a.min, 50);
  const pts = vals.map((v, i) => [10 + i * (298 / (vals.length - 1)), bottom - ((v - min) / (max - min || 1)) * (bottom - top)]);
  const col = color(a.color || 'red');
  const id = nextId();
  let s = `<defs><linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${col}" stop-opacity=".20"/><stop offset="1" stop-color="${col}" stop-opacity=".02"/></linearGradient></defs>`;
  for (let i = 0; i <= 2; i++) s += hline(top + i * ((bottom - top) / 2), 10, 302);
  if (a.band) s += `<rect x="10" y="${top}" width="112" height="${bottom - top}" fill="#FCEDEF" opacity=".6"/>`;
  s += `<path d="M${pts[0][0]},${bottom} ${pts.map(p => `L${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(' ')} L${pts.at(-1)[0]},${bottom} Z" fill="url(#${id})"/>`;
  s += poly(pts, col, 1.6);
  list(a.ylabels).forEach((t, i, all) => label(316, top + i * ((bottom - top) / Math.max(1, all.length - 1)) + 3, t, 'text-anchor="end"'));
  list(a.labels).forEach((t, i, all) => label(10 + i * (298 / Math.max(1, all.length - 1)), h - 4, t, i === 0 ? 'text-anchor="start"' : i === all.length - 1 ? 'text-anchor="end"' : 'text-anchor="middle"'));
  return frame(h, s, a.aria || '心率波形图');
}

/** 双系列堆叠柱（快速眼动 + 深度睡眠）：data-values / data-values-b 由序列注入。 */
function dualbars(a) {
  const h = 136, top = 14, bottom = 106;
  const va = nums(a.values, [0]), vb = nums(a['values-b'], [0]);
  const max = num(a.max, 4), slot = 300 / va.length, bw = 13;
  let s = '';
  for (let i = 0; i <= 3; i++) s += hline(top + i * ((bottom - top) / 3));
  if (a.avg) {
    const ay = bottom - (Number(a.avg) / max) * (bottom - top);
    s += `<line x1="8" y1="${ay}" x2="312" y2="${ay}" stroke="${color(a['avg-color'] || 'lavender')}" stroke-width="1.2" vector-effect="non-scaling-stroke"/>`;
  }
  va.forEach((v, i) => {
    const x = 10 + slot * i + (slot - bw) / 2;
    const ha = (v / max) * (bottom - top), hb = ((vb[i] || 0) / max) * (bottom - top);
    s += `<rect x="${x}" y="${(bottom - hb).toFixed(1)}" width="${bw}" height="${hb.toFixed(1)}" fill="${color(a['color-b'] || 'purple')}"/>`;
    s += `<rect x="${x}" y="${(bottom - hb - ha).toFixed(1)}" width="${bw}" height="${ha.toFixed(1)}" fill="${color(a['color-a'] || 'teal')}"/>`;
  });
  list(a.labels).forEach((t, i) => label(10 + slot * i + slot / 2, 122, t, 'text-anchor="middle"'));
  return frame(h, s, a.aria || '双系列堆叠柱状图');
}

/** 生命体征卡片中的迷你点线图：14 点同源序列由 data-values 注入。 */
function vitalsMini(a) {
  const h = 62, vals = nums(a.values, [0, 0]);
  const max = Math.max(...vals), min = Math.min(...vals);
  const pts = vals.map((v, i) => [12 + i * (296 / (vals.length - 1)), 48 - ((v - min) / Math.max(1, max - min)) * 32]);
  let s = `${hline(15, 8, 312)}${hline(31, 8, 312)}${hline(47, 8, 312)}`;
  s += poly(pts, '#C9CCD1', 1.4);
  s += dot(pts.at(-1)[0], pts.at(-1)[1], 3.6, color(a.color || 'lavender'));
  return frame(h, s, a.aria || '近 14 日迷你趋势');
}

const RENDERERS = { line, area, bars, hist, step, dots, ring: sleepRing, disc, stack, capsule, spark, wave, dualbars, mini: vitalsMini };

/** 构建期调用：把占位元素替换为完整 SVG，返回 { html, count }。 */
export function expandCharts(html) {
  let count = 0;
  const out = html.replace(/<div\s+class="chart"([^>]*?)><\/div>/g, (full, attrsRaw) => {
    const attrs = {};
    for (const m of attrsRaw.matchAll(/([a-z][a-z0-9-]*)\s*=\s*"([^"]*)"/gi)) attrs[m[1].toLowerCase()] = m[2];
    const kind = attrs['data-chart'];
    const render = RENDERERS[kind];
    if (!render) return full;
    count++;
    const clean = { ...attrs };
    Object.keys(clean).forEach(k => { if (k.startsWith('data-')) clean[k.slice(5)] = clean[k]; });
    return `<div class="chart chart-${esc(kind)}">${render(clean)}</div>`;
  });
  return { html: out, count };
}
