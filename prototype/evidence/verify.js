/* 无头浏览器验证：把结果写入 <pre id="verify-result">，供 --dump-dom 读取 */
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
