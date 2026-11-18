/* StressWatch 界面原型 · 本地交互，无外部依赖 · v1.0.0 */
/* StressWatch UI 原型 · 本地交互层
   所有行为均为 DOM 内 mock：无网络、无持久化、无账号、无后端。 */
(function () {
  'use strict';
  const META = window.PROTOTYPE_META || { screens: [] };
  const byId = Object.fromEntries(META.screens.map(s => [s.id, s]));
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const phone = $('#phone');
  const scroller = $('#screen-scroller');
  const tabbar = $('#tabbar');
  const toastEl = $('#toast');
  const backdrop = $('#sheet-backdrop');
  const sheetContent = $('#sheet-content');
  const sheetTitle = $('#sheet-title');
  let activeId = 'today';
  let lastTrigger = null;
  let toastTimer = null;
  let canvas = { w: 390, h: 844 };

  /** 桌面窗口较矮时压缩画布高度，保证整机可见；手机视口交回 CSS 全屏布局。 */
  function fitPhone() {
    if (window.innerWidth <= 900) {
      phone.style.width = '';
      phone.style.height = '';
      return;
    }
    phone.style.width = `${canvas.w}px`;
    phone.style.height = `${Math.min(canvas.h, Math.max(560, window.innerHeight - 118))}px`;
  }
  window.addEventListener('resize', fitPhone);

  function toast(message) {
    toastEl.textContent = message;
    toastEl.classList.add('is-visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove('is-visible'), 2600);
  }

  function updateInspector(meta) {
    if (!meta) return;
    $('#insp-title').textContent = meta.title;
    $('#insp-group').textContent = `${meta.group} · ${meta.subtitle}`;
    $('#insp-sources').innerHTML = meta.sources.map(f => `<code>${f.replace(/^.*\//, '')}</code>`).join('');
    $('#insp-states').innerHTML = meta.states.map(s => `<span class="chip">${s}</span>`).join('');
    $('#insp-notes').innerHTML = meta.notes.map(n => `<li>${n}</li>`).join('');
  }

  function showScreen(id, opts = {}) {
    const meta = byId[id];
    if (!meta) return false;
    $$('.screen').forEach(el => el.classList.toggle('is-active', el.dataset.screen === id));
    phone.dataset.tone = meta.tone;
    $('#status-time').textContent = meta.time;
    tabbar.hidden = !meta.tabbar;
    $$('.tab-item').forEach(btn => {
      const active = btn.dataset.tab === meta.tab && !!meta.tab;
      btn.classList.toggle('is-active', active);
      btn.setAttribute('aria-current', active ? 'page' : 'false');
    });
    $$('.side-item').forEach(btn => btn.classList.toggle('is-active', btn.dataset.go === id));
    const select = $('#mobile-select');
    if (select) select.value = id;
    document.title = `${meta.title} · StressWatch 界面原型`;
    updateInspector(meta);
    activeId = id;
    if (!opts.keepScroll) scroller.scrollTop = 0;
    if (!opts.silent) {
      const target = $(`#screen-${id}`);
      if (target) { target.setAttribute('tabindex', '-1'); target.focus({ preventScroll: true }); }
    }
    return true;
  }

  /* ---------- 底部说明弹层 ---------- */
  function openSheet(name, trigger) {
    let tpl = document.getElementById(`sheet-${name}`);
    let note = '';
    if (!tpl) {
      tpl = document.getElementById('sheet-generic');
      note = `触发位置：${trigger ? (trigger.getAttribute('aria-label') || trigger.textContent.trim().slice(0, 24)) : '未提供'}。`;
    }
    lastTrigger = trigger || null;
    sheetTitle.textContent = tpl.dataset.title || '说明';
    sheetContent.replaceChildren(tpl.content.cloneNode(true));
    // 展开弹层内的图表占位（构建期已展开的会保持原样）
    const noteEl = sheetContent.querySelector('#sheet-generic-note');
    if (noteEl && note) noteEl.textContent = note;
    backdrop.hidden = false;
    const close = $('[data-close-sheet]');
    if (close) close.focus({ preventScroll: true });
    return true;
  }
  function closeSheet() {
    if (backdrop.hidden) return false;
    backdrop.hidden = true;
    sheetContent.replaceChildren();
    if (lastTrigger && document.contains(lastTrigger)) lastTrigger.focus({ preventScroll: true });
    lastTrigger = null;
    return true;
  }

  /* ---------- 分段控件 ---------- */
  function applySegment(group, value) {
    const root = $(`[data-segment-group="${group}"]`);
    if (!root) return;
    $$('button', root).forEach(b => b.setAttribute('aria-pressed', String(b.dataset.value === value)));
    const screen = $(`#screen-${activeId}`);
    if (group === 'sleep-range') {
      if (value === 'month') return showScreen('sleep-month');
      if (value === 'day') return showScreen('sleep-day');
      $$('[data-sleep-panel]', screen).forEach(p => { p.hidden = p.dataset.sleepPanel !== 'week'; });
      return;
    }
    const other = group === 'trends-range' ? 'week' : '30d';
    $$('[data-range-panel]', screen).forEach(p => {
      const key = p.dataset.rangePanel;
      p.hidden = key === 'other' ? value === other : value !== other;
    });
  }

  /* ---------- 文章阅读 ---------- */
  function selectArticle(name) {
    const screen = $('#screen-ai-article');
    $$('[data-article-body]', screen).forEach(el => { el.hidden = el.dataset.articleBody !== name; });
    $$('[data-article]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.article === name)));
    scroller.scrollTop = 0;
  }

  /* ---------- 事件委托 ---------- */
  document.addEventListener('click', (event) => {
    const btn = event.target.closest('button, [data-go]');
    if (!btn) {
      if (event.target === backdrop) closeSheet();
      return;
    }
    if (btn.hasAttribute('data-close-sheet')) { closeSheet(); return; }
    if (btn.dataset.go) { closeSheet(); showScreen(btn.dataset.go); return; }
    if (btn.dataset.tab) {
      if (btn.dataset.tab === 'settings') {
        toast('「设置」页面未包含在 53 张参考截图中，按范围要求不补绘。');
        return;
      }
      const map = { today: 'today', actions: 'actions', trends: 'trends', health: 'health' };
      showScreen(map[btn.dataset.tab]);
      return;
    }
    if (btn.dataset.subtab) { showScreen(btn.dataset.subtab); return; }
    if (btn.dataset.sheet) { openSheet(btn.dataset.sheet, btn); return; }
    if (btn.dataset.mock) { toast(btn.dataset.mock); return; }
    if (btn.dataset.segmentGroup) return; // 由下方按钮分支处理
    const segment = btn.closest('[data-segment-group]');
    if (segment && btn.dataset.value) { applySegment(segment.dataset.segmentGroup, btn.dataset.value); return; }
    if (btn.dataset.chatToggle !== undefined) {
      $$('[data-chat-toggle]').forEach(b => { if (b !== btn) b.setAttribute('aria-pressed', 'false'); });
      btn.setAttribute('aria-pressed', String(btn.getAttribute('aria-pressed') !== 'true'));
      toast('反馈已记录在本地 mock，未发送到服务端');
      return;
    }
    if (btn.dataset.suggest) {
      const input = $('#chat-input');
      input.value = btn.dataset.suggest;
      input.dispatchEvent(new Event('input', { bubbles: true }));
      input.focus();
      return;
    }
    if (btn.dataset.article) { selectArticle(btn.dataset.article); return; }
    if (btn.dataset.scrollTo) {
      const target = document.getElementById(btn.dataset.scrollTo);
      if (target) target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      return;
    }
    if (btn.dataset.viewport) {
      $$('[data-viewport]').forEach(b => b.setAttribute('aria-pressed', String(b === btn)));
      canvas = btn.dataset.viewport === '430' ? { w: 430, h: 932 } : { w: 390, h: 844 };
      fitPhone();
      return;
    }
    if (btn.dataset.action) {
      switch (btn.dataset.action) {
        case 'toggle-tooltip': {
          const tip = $('#hrv-tooltip');
          tip.hidden = !tip.hidden;
          break;
        }
        case 'close-promo': { const promo = $('#trends-promo'); if (promo) promo.hidden = true; break; }
        case 'scroll-top': { scroller.scrollTo({ top: 0, behavior: 'smooth' }); break; }
        case 'increment': {
          const node = document.getElementById(btn.dataset.target);
          if (!node) break;
          const step = Number(btn.dataset.step) || 1, max = Number(btn.dataset.max) || 9999;
          const next = Math.min(max, (Number(node.textContent) || 0) + step);
          node.textContent = String(next);
          node.closest('.habit').classList.add('is-updated');
          toast(`已记录 ${next}（本地 mock，未写入健康数据）`);
          setTimeout(() => node.closest('.habit').classList.remove('is-updated'), 600);
          break;
        }
        default: break;
      }
      return;
    }
  });

  backdrop.addEventListener('click', (e) => { if (e.target === backdrop) closeSheet(); });
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (!backdrop.hidden) { closeSheet(); return; }
    if (activeId !== 'today' && !byId[activeId].tabbar) showScreen('today');
  });

  /* ---------- 问问 AI ---------- */
  const chatInput = $('#chat-input');
  const chatSend = $('#chat-send');
  const chatForm = $('#chat-form');
  if (chatInput && chatSend && chatForm) {
    chatInput.addEventListener('input', () => { chatSend.disabled = chatInput.value.trim().length === 0; });
    chatForm.addEventListener('submit', (e) => {
      e.preventDefault();
      const text = chatInput.value.trim();
      if (!text) { chatSend.disabled = true; return; }
      const loading = $('#chat-loading'), reply = $('#chat-reply');
      chatSend.disabled = true;
      loading.hidden = false; reply.hidden = true;
      setTimeout(() => {
        loading.hidden = true;
        reply.innerHTML = `<strong>你问：</strong>${escapeText(text)}<br><br>这是界面演示用的本地 mock 回答<span class="mock-tag">MOCK</span>：截图未提供真实问答数据，此处不编造健康结论。`;
        reply.hidden = false;
        chatSend.disabled = false;
        reply.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      }, 900);
    });
  }
  function escapeText(s) { const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }

  /* ---------- 侧栏搜索与移动端选择 ---------- */
  const sideSearch = $('#side-search');
  if (sideSearch) sideSearch.addEventListener('input', () => {
    const q = sideSearch.value.trim().toLowerCase();
    $$('.side-item').forEach(item => { item.hidden = q !== '' && !item.textContent.toLowerCase().includes(q); });
    $$('.side-label').forEach(label => {
      const group = label.nextElementSibling;
      if (group && group.classList.contains('side-group')) label.hidden = $$('.side-item:not([hidden])', group).length === 0;
    });
  });
  const mobileSelect = $('#mobile-select');
  if (mobileSelect) mobileSelect.addEventListener('change', () => showScreen(mobileSelect.value));

  /* ---------- 初始化与验证接口 ---------- */
  fitPhone();
  const initial = location.hash.replace(/^#/, '');
  showScreen(byId[initial] ? initial : 'today', { silent: true });
  window.__PROTOTYPE__ = {
    showScreen,
    openSheet,
    closeSheet,
    applySegment,
    selectArticle,
    screenIds: META.screens.map(s => s.id),
    get activeScreen() { return activeId; },
    get sheetOpen() { return !backdrop.hidden; },
    toast,
  };
})();
