// 图标定义：全部为本地内联 SVG，不引用任何外部资源。
// 视图统一 24x24，使用 currentColor 继承文字颜色，便于主题化。
const p = (d, extra = '') => `<path d="${d}" ${extra}/>`;
const circle = (cx, cy, r, extra = '') => `<circle cx="${cx}" cy="${cy}" r="${r}" ${extra}/>`;

export const icons = {
  'back': `${p('M15 5l-7 7 7 7')}${p('M8 12h11')}`,
  'close': `${p('M6 6l12 12')}${p('M18 6L6 18')}`,
  'share': `${p('M19.5 8.5a6.5 6.5 0 1 0-1.9 4.6')}${p('M19.5 4.5v4h-4')}${p('M4.5 14.5v4a1 1 0 0 0 1 1h13a1 1 0 0 0 1-1v-4')}`,
  'hex': `<path d="M12 2.6l7.5 4.4v10L12 21.4 4.5 17V7z"/><path d="M12 8.2l3.8 2.2v4.4L12 17l-3.8-2.2v-4.4z"/>`,
  'info': `${circle(12, 12, 9)}${p('M12 11v5.5', 'stroke-linecap="round"')}${circle(12, 7.6, 0.9, 'fill="currentColor" stroke="none"')}`,
  'chevron-right': p('M9 5l7 7-7 7'),
  'chevron-left': p('M15 5l-7 7 7 7'),
  'chevron-down': p('M5 9l7 7 7-7'),
  'sort': `${p('M7 9l5-5 5 5')}${p('M7 15l5 5 5-5')}`,
  'clock': `${circle(12, 12, 9)}${p('M12 7v5.2l3.2 2')}`,
  'trend': `${p('M5 19V12', 'stroke-width="3.4" stroke-linecap="round"')}${p('M12 19V6', 'stroke-width="3.4" stroke-linecap="round"')}${p('M19 19V10', 'stroke-width="3.4" stroke-linecap="round"')}`,
  'play': p('M8 5.5l11 6.5-11 6.5z', 'fill="currentColor" stroke="none"'),
  'heart': p('M12 20.3s-8-4.9-8-10.2a4.6 4.6 0 0 1 8-3.1 4.6 4.6 0 0 1 8 3.1c0 5.3-8 10.2-8 10.2z'),
  'settings': `${circle(12, 12, 9, 'stroke-width="2.4"')}${circle(12, 12, 3.1, 'fill="currentColor" stroke="none"')}`,
  'today': `${circle(12, 12, 9, 'fill="currentColor" stroke="none"')}${p('M12 7.2v5.4', 'stroke="#fff" stroke-width="2.3" stroke-linecap="round"')}${circle(12, 16.3, 1.15, 'fill="#fff" stroke="none"')}`,
  'ghost': `<path d="M4.6 20V11a7.4 7.4 0 0 1 14.8 0v9l-2.5-2-2.5 2-2.4-2-2.5 2-2.5-2z"/>${circle(9.3, 11.2, 1.15, 'fill="currentColor" stroke="none"')}${circle(14.7, 11.2, 1.15, 'fill="currentColor" stroke="none"')}`,
  'sun': `${circle(12, 12, 4)}${p('M12 2v2.2M12 19.8V22M2 12h2.2M19.8 12H22M4.9 4.9l1.6 1.6M17.5 17.5l1.6 1.6M19.1 4.9l-1.6 1.6M6.5 17.5l-1.6 1.6')}`,
  'moon': p('M20 15.2A8.6 8.6 0 0 1 8.8 4 8.7 8.7 0 1 0 20 15.2z'),
  'moon-star': `<path d="M19.6 15.6A8.2 8.2 0 0 1 8.4 4.4a8.3 8.3 0 1 0 11.2 11.2z"/><path d="M16.5 3l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z" fill="currentColor" stroke="none"/>`,
  'lungs': p('M12 3v9M9 8.5c-2-1.6-4.4.2-4.4 3.2V18a3 3 0 0 0 3 3h1.2c.9 0 1.5-.7 1.5-1.6V10.6M15 8.5c2-1.6 4.4.2 4.4 3.2V18a3 3 0 0 1-3 3h-1.2c-.9 0-1.5-.7-1.5-1.6V10.6'),
  'drop': p('M12 3.2c3.4 4.3 5.6 7.1 5.6 9.7a5.6 5.6 0 1 1-11.2 0c0-2.6 2.2-5.4 5.6-9.7z'),
  'thermo': `<path d="M10 13.8V5.5a2 2 0 0 1 4 0v8.3a4 4 0 1 1-4 0z"/>${p('M12 10v7')}`,
  'sparkle': `<path d="M12 2.5l1.9 6.1 6.1 1.9-6.1 1.9-1.9 6.1-1.9-6.1-6.1-1.9 6.1-1.9z" fill="currentColor" stroke="none"/>`,
  'star': p('M12 3.2l2.6 5.6 6 .8-4.4 4.2 1.1 6-5.3-2.9-5.3 2.9 1.1-6-4.4-4.2 6-.8z'),
  'bed': `${p('M3 18v-9')}${p('M3 13h18v5')}${p('M21 18v-4a3 3 0 0 0-3-3h-6v3')}${circle(7.5, 10.5, 1.6)}`,
  'bike': `${circle(5.5, 17, 3.3)}${circle(18.5, 17, 3.3)}${p('M5.5 17l4-8h4l3.5 8')}${p('M9.5 9h5l2 3')}${circle(15.5, 5.5, 1.1)}`,
  'run': `${circle(14.5, 4.5, 1.8)}${p('M8 21l3-5 2.5-2-1-4-3.5 2-2 3')}${p('M12.5 10l3.5 2 3 .2')}${p('M14.5 14l3 7')}`,
  'weights': `${p('M4 9v6M7 7v10M17 7v10M20 9v6')}${p('M7 12h10')}`,
  'steps': `<path d="M8.4 5.2c1.6 0 2.3 1.2 2.2 2.6-.1 1.5-1 2.4-.5 3.6.5 1.2 2.3 1.7 2.2 3.4-.1 1.5-1.3 2.5-3 2.5-1.8 0-3-1.3-2.8-3 .1-1.3 1.3-2 .9-3.3-.4-1.2-1.8-1.6-1.7-3.1.1-1.6 1.1-2.7 2.7-2.7z"/><path d="M16.6 8.2c1.3 0 1.9 1 1.8 2.1-.1 1.2-.8 1.9-.4 2.9.4 1 1.9 1.4 1.8 2.8-.1 1.2-1.1 2-2.4 2-1.5 0-2.5-1-2.3-2.4.1-1.1 1-1.6.7-2.7-.3-.9-1.5-1.3-1.4-2.5.1-1.3.9-2.2 2.2-2.2z"/>`,
  'vo2': p('M12 20.3s-8-4.9-8-10.2a4.6 4.6 0 0 1 8-3.1 4.6 4.6 0 0 1 8 3.1c0 5.3-8 10.2-8 10.2z'),
  'leaf': p('M20 4C9 4 4 9 4 15a5 5 0 0 0 5 5c6 0 11-5 11-16z') + p('M5 19c3-5 6-8 11-11'),
  'plus': p('M12 5v14M5 12h14'),
  'copy': `<rect x="8" y="8" width="11" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h1"/>`,
  'thumb-up': p('M7 10v9H4a1 1 0 0 1-1-1v-7a1 1 0 0 1 1-1h3z') + p('M7 10l4.2-6.4a1.6 1.6 0 0 1 2.9 1.1L13.4 9h4.8a2 2 0 0 1 1.9 2.6l-2 6a2 2 0 0 1-1.9 1.4H7'),
  'thumb-down': p('M7 14V5H4a1 1 0 0 0-1 1v7a1 1 0 0 0 1 1h3z') + p('M7 14l4.2 6.4a1.6 1.6 0 0 0 2.9-1.1L13.4 15h4.8a2 2 0 0 0 1.9-2.6l-2-6a2 2 0 0 0-1.9-1.4H7'),
  'arrow-up': `${p('M12 19V5')}${p('M6.5 10.5L12 5l5.5 5.5')}`,
  'pencil': p('M4 20l4.2-1 10.4-10.4a2 2 0 0 0-2.8-2.8L5.4 16.2z') + p('M14.5 7.5l2.8 2.8'),
  'calendar': `<rect x="3.5" y="5.5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3.5v4M16 3.5v4"/>`,
  'sound': `${p('M4 9v6h3.5l4.5 3.5V5.5L7.5 9z')}${p('M16 9a4 4 0 0 1 0 6')}${p('M18.7 6.4a7.6 7.6 0 0 1 0 11.2')}`,
  'lotus': p('M12 20c-5 0-8-3.4-8-7 0-1.8 1.5-3 2.8-2.6C6.4 7.2 8.6 5 12 5s5.6 2.2 5.2 5.4c1.3-.4 2.8.8 2.8 2.6 0 3.6-3 7-8 7z') + p('M12 20c-2.5-2.8-3.2-5.6-2.2-8.4M12 20c2.5-2.8 3.2-5.6 2.2-8.4'),
  'coffee': `<path d="M4 8h13v6a5 5 0 0 1-5 5H9a5 5 0 0 1-5-5z"/><path d="M17 9h1.8a2.4 2.4 0 0 1 0 4.8H17"/><path d="M8 3.5v2M12 3.5v2"/>`,
  'water': p('M12 3.2c3.4 4.3 5.6 7.1 5.6 9.7a5.6 5.6 0 1 1-11.2 0c0-2.6 2.2-5.4 5.6-9.7z'),
  'gauge': `${p('M4.5 17a8.5 8.5 0 1 1 15 0')}${p('M12 12l4-4')}${circle(12, 17, 1.2, 'fill="currentColor" stroke="none"')}`,
  'check': p('M5 12.5l4.5 4.5L19 7.5'),
  'warning': p('M12 3.6l9 16H3z') + p('M12 9v4.5', 'stroke-linecap="round"') + circle(12, 16.7, 0.9, 'fill="currentColor" stroke="none"'),
  'menu': p('M4 7h16M4 12h16M4 17h16'),
  'search': `${circle(10.8, 10.8, 6.3)}${p('M15.5 15.5L20 20')}`,
  'chat': p('M4.5 5.5h15v11h-9l-5 3.5v-3.5h-1z') + p('M9 10h6M9 13h4'),
  'flame': p('M12 21c4 0 6.5-2.7 6.5-6.2 0-3-1.8-5.2-3.2-6.7-.4 1.6-1.3 2.4-2.2 2.8.4-3.4-1.2-6-3.6-8-.3 2.6-1.5 4-3 5.6C5 10 5.5 12 5.5 14.8 5.5 18.3 8 21 12 21z'),
  'noise': `${p('M4 9v6h3l4 3.5v-13L7 9z')}${p('M15 9.5l4 5M19 9.5l-4 5')}`,
  'target': `${circle(12, 12, 9)}${circle(12, 12, 5)}${circle(12, 12, 1.4, 'fill="currentColor" stroke="none"')}`,
  'refresh': `${p('M19.5 8.5a7.5 7.5 0 1 0-1.8 5.4')}${p('M19.5 4.5v4h-4')}`,
};

/** 生成内联 SVG 图标；name 不存在时返回空串，避免注入未知内容。 */
export function icon(name, className = 'icon', label = '') {
  const body = icons[name];
  if (!body) return '';
  const aria = label ? ` role="img" aria-label="${label}"` : ' aria-hidden="true" focusable="false"';
  return `<svg class="${className}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"${aria}>${body}</svg>`;
}
