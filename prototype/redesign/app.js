/* ============================================================
   Healthy 原型交互：主题 / 页面 / 状态档 / Tab / FAB / 开关
   ============================================================ */
(function () {
  // 四档状态数据（Apple 系统色语义）
  const STATES = {
    excellent: { word: '状态优秀', score: 88, stress: 24, color: 'var(--state-excellent)', advice: '状态很好，保持规律作息，去接触一点自然光吧。', pos: 0.86 },
    normal:    { word: '状态正常', score: 72, stress: 42, color: 'var(--state-normal)',    advice: '整体平稳，记得适时起身活动，别久坐太久。', pos: 0.62 },
    elevated:  { word: '注意压力', score: 58, stress: 66, color: 'var(--state-elevated)',  advice: '压力略高，试着放慢节奏，做几组深呼吸。', pos: 0.34 },
    overload:  { word: '压力过载', score: 41, stress: 84, color: 'var(--state-overload)',  advice: '压力偏高，建议尽快休息，优先保证睡眠。', pos: 0.12 }
  };
  let currentState = 'excellent';

  function applyState(key) {
    const s = STATES[key];
    if (!s) return;
    currentState = key;
    document.querySelectorAll('[data-state-word]').forEach(el => el.textContent = s.word);
    document.querySelectorAll('[data-state-score]').forEach(el => el.textContent = s.score);
    document.querySelectorAll('[data-state-stress]').forEach(el => el.textContent = s.stress);
    document.querySelectorAll('[data-state-advice]').forEach(el => el.textContent = s.advice);
    document.querySelectorAll('[data-state-color]').forEach(el => {
      el.style.color = s.color;
      if (el.hasAttribute('data-state-bg')) el.style.background = s.color;
    });
    document.querySelectorAll('[data-state-marker]').forEach(el => {
      el.style.color = s.color;
      el.style.marginLeft = `calc(${s.pos} * (100% - 18px))`;
    });
    // 核心环进度
    document.querySelectorAll('[data-ring-progress]').forEach(circle => {
      const c = 2 * Math.PI * 96;
      circle.style.strokeDasharray = `${c}`;
      circle.style.strokeDashoffset = `${c * (1 - s.score / 100)}`;
      circle.style.stroke = s.color;
    });
    // 状态切换按钮高亮
    document.querySelectorAll('[data-set-state]').forEach(b => {
      b.setAttribute('aria-pressed', String(b.dataset.setState === key));
    });
  }

  // 主题
  function setTheme(t) {
    document.documentElement.setAttribute('data-theme', t);
    document.querySelectorAll('[data-theme-btn]').forEach(b => {
      b.setAttribute('aria-pressed', String(b.dataset.themeBtn === t));
    });
  }

  // 页面切换（iOS / Watch 各自独立）
  function showPage(id, device) {
    const scope = device === 'watch' ? '.watch .screen' : '.iphone .screen';
    const root = document.querySelector(scope);
    if (!root) return;
    root.querySelectorAll('.page').forEach(p => p.classList.toggle('active', p.dataset.page === id));
    root.querySelectorAll('.app-scroll').forEach(s => { s.scrollTop = 0; });
    // 侧栏高亮
    document.querySelectorAll('.nav-item').forEach(item => {
      item.classList.toggle('active', item.dataset.target === id && item.dataset.device === (device || 'ios'));
    });
    // 更新 tab 高亮
    const tabMap = { today: 'today', action: 'action', trends: 'trends', health: 'health' };
    document.querySelectorAll('.iphone .tab').forEach(t => {
      t.classList.toggle('active', t.dataset.tab === tabMap[id]);
    });
  }

  // 图标水合：把 <i data-icon="moon" data-size="22" data-color="..."> 替换为 SVG
  function hydrateIcons() {
    document.querySelectorAll('i[data-icon]').forEach(el => {
      const size = el.dataset.size || 22;
      const color = el.dataset.color || el.style.color || 'currentColor';
      const sw = el.dataset.sw || 1.8;
      el.outerHTML = icon(el.dataset.icon, { size, color, sw });
    });
  }

  function init() {
    hydrateIcons();
    // 主题按钮
    document.querySelectorAll('[data-theme-btn]').forEach(b => {
      b.addEventListener('click', () => setTheme(b.dataset.themeBtn));
    });
    setTheme('light');

    // 状态切换按钮
    document.querySelectorAll('[data-set-state]').forEach(b => {
      b.addEventListener('click', () => applyState(b.dataset.setState));
    });
    applyState('excellent');

    // 侧栏导航
    document.querySelectorAll('.nav-item').forEach(item => {
      item.addEventListener('click', () => {
        const dev = item.dataset.device || 'ios';
        showPage(item.dataset.target, dev);
        if (dev === 'watch') {
          document.querySelector('.watch')?.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
      });
    });

    // iPhone Tab
    document.querySelectorAll('.iphone .tab').forEach(t => {
      t.addEventListener('click', () => showPage(t.dataset.tab, 'ios'));
    });

    // Watch 底部数字表冠：切到下一页
    document.querySelectorAll('[data-watch-next]').forEach(b => {
      b.addEventListener('click', () => {
        const order = ['w-dashboard', 'w-hrv', 'w-stress', 'w-water', 'w-caffeine'];
        const cur = order.findIndex(p => document.querySelector(`.watch .page[data-page="${p}"]`)?.classList.contains('active'));
        showPage(order[(cur + 1) % order.length], 'watch');
      });
    });

    // FAB 菜单
    const fab = document.querySelector('.fab');
    const menu = document.querySelector('.fab-menu');
    if (fab && menu) {
      fab.addEventListener('click', (e) => {
        e.stopPropagation();
        menu.classList.toggle('open');
        fab.querySelector('svg').innerHTML = menu.classList.contains('open')
          ? ICONS.xmark : '<path d="M12 5v14M5 12h14"/>';
      });
      menu.querySelectorAll('button').forEach(b => {
        b.addEventListener('click', () => {
          menu.classList.remove('open');
          fab.querySelector('svg').innerHTML = '<path d="M12 5v14M5 12h14"/>';
          const t = b.dataset.record;
          if (t) showToast(`已打开「${t}」记录`);
        });
      });
      document.addEventListener('click', () => {
        menu.classList.remove('open');
        fab.querySelector('svg').innerHTML = '<path d="M12 5v14M5 12h14"/>';
      });
    }

    // 开关
    document.querySelectorAll('.switch').forEach(sw => {
      sw.addEventListener('click', () => {
        sw.setAttribute('aria-checked', String(sw.getAttribute('aria-checked') !== 'true'));
      });
    });

    // Segmented / tab-in-page
    document.querySelectorAll('.segmented button, .seg-group button').forEach(b => {
      b.addEventListener('click', () => {
        b.parentElement.querySelectorAll('button').forEach(x => x.setAttribute('aria-pressed', 'false'));
        b.setAttribute('aria-pressed', 'true');
      });
    });

    // 收藏 / 心形等切换反馈
    document.querySelectorAll('[data-toggle-fill]').forEach(b => {
      b.addEventListener('click', () => b.classList.toggle('on'));
    });

    // 返回按钮
    document.querySelectorAll('.nav-inline .back').forEach(b => {
      b.addEventListener('click', () => showPage(b.dataset.back || 'today', 'ios'));
    });

    // 卡片点击进详情（带 data-goto）
    document.querySelectorAll('[data-goto]').forEach(el => {
      el.addEventListener('click', (e) => {
        e.stopPropagation();
        showPage(el.dataset.goto, el.dataset.gotoDevice || 'ios');
      });
    });
  }

  function showToast(msg) {
    let t = document.querySelector('.toast');
    if (!t) {
      t = document.createElement('div');
      t.className = 'toast';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(() => t.classList.remove('show'), 1800);
  }

  document.addEventListener('DOMContentLoaded', init);
})();
