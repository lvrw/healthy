/* ============================================================
   SF Symbols 风格图标库（stroke 线性，统一 1.8）
   icon(name, {size, color, sw}) → <svg>
   ============================================================ */
(function (global) {
  const P = {
    house:'<path d="M3 10.5 12 3l9 7.5"/><path d="M5.5 9.5V20h13V9.5"/><path d="M9.5 20v-6h5v6"/>',
    grid:'<rect x="3" y="3" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="3" width="7.5" height="7.5" rx="2"/><rect x="3" y="13.5" width="7.5" height="7.5" rx="2"/><rect x="13.5" y="13.5" width="7.5" height="7.5" rx="2"/>',
    trend:'<path d="M3 17l5-5 4 3 8-8"/><path d="M15 7h5v5"/>',
    health:'<path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.9a4.7 4.7 0 0 1 8.5 2.3C20.5 15 12 20.5 12 20.5Z"/><path d="M7 12h3l1.5-2.5L14 14l1.5-2H17"/>',
    moon:'<path d="M20 14.5A8 8 0 1 1 9.5 4a6.3 6.3 0 0 0 10.5 10.5Z"/>',
    fork:'<path d="M7 3v7a2.5 2.5 0 0 0 5 0V3"/><path d="M9.5 3v18"/><path d="M17 3c-1.5 2-2 4.5-2 7h4V3z"/><path d="M17 10v11"/>',
    drop:'<path d="M12 3s6 6.4 6 10.4A6 6 0 0 1 6 13.4C6 9.4 12 3 12 3Z"/>',
    coffee:'<path d="M4 8h13v6.5A4.5 4.5 0 0 1 12.5 19h-4A4.5 4.5 0 0 1 4 14.5Z"/><path d="M17 9h1.5a2.5 2.5 0 0 1 0 5H17"/><path d="M8 3.5c0 1-1 1.5-1 2.5M12 3.5c0 1-1 1.5-1 2.5"/>',
    figure:'<circle cx="12" cy="4.5" r="2"/><path d="M12 7v6M12 9l-4 2M12 9l4 2M12 13l-3 7M12 13l3 7"/>',
    sun:'<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9 7 7M17 17l2.1 2.1M19.1 4.9 17 7M7 17l-2.1 2.1"/>',
    leaf:'<path d="M20 4C10 4 5 8 5 14a5 5 0 0 0 5 5c6 0 10-5 10-15Z"/><path d="M4 20c3-5 7-8 12-10"/>',
    footprint:'<ellipse cx="8" cy="14" rx="3" ry="5"/><circle cx="7" cy="7" r="1.6"/><circle cx="10" cy="9" r="1.6"/><ellipse cx="17" cy="13" rx="2.6" ry="4.5"/><circle cx="16" cy="7.5" r="1.4"/><circle cx="18.5" cy="9" r="1.4"/>',
    wave:'<path d="M3 12h2l2-5 3 12 3-15 3 12 2-4h3"/>',
    gear:'<circle cx="12" cy="12" r="3.2"/><path d="M12 2.5v2.2M12 19.3v2.2M4.3 4.3l1.6 1.6M18.1 18.1l1.6 1.6M2.5 12h2.2M19.3 12h2.2M4.3 19.7l1.6-1.6M18.1 5.9l1.6-1.6"/>',
    share:'<path d="M12 15V3M8 7l4-4 4 4"/><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/>',
    refresh:'<path d="M20 11a8 8 0 1 0-2 6"/><path d="M20 5v6h-6"/>',
    chevronR:'<path d="m9 5 7 7-7 7"/>',
    chevronL:'<path d="m15 5-7 7 7 7"/>',
    plus:'<path d="M12 5v14M5 12h14"/>',
    xmark:'<path d="M6 6l12 12M18 6 6 18"/>',
    sparkles:'<path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6Z"/><path d="M18.5 15l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8Z"/>',
    info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
    search:'<circle cx="11" cy="11" r="7"/><path d="m16.5 16.5 4 4"/>',
    bell:'<path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6Z"/><path d="M10 19a2 2 0 0 0 4 0"/>',
    heart:'<path d="M12 20.5S3.5 15 3.5 9.2A4.7 4.7 0 0 1 12 6.9a4.7 4.7 0 0 1 8.5 2.3C20.5 15 12 20.5 12 20.5Z"/>',
    ecg:'<path d="M3 12h4l2-4 3 8 2.5-5 2 3h4.5"/>',
    lungs:'<path d="M12 4v8"/><path d="M12 8c-2 0-3-2-5-2-1.5 0-2 2-2.5 5-.4 2.5-.2 6 1.5 6 2 0 3-2 3.5-5 .3-1.7.5-3.5 2.5-4Z"/><path d="M12 8c2 0 3-2 5-2 1.5 0 2 2 2.5 5 .4 2.5.2 6-1.5 6-2 0-3-2-3.5-5-.3-1.7-.5-3.5-2.5-4Z"/>',
    thermometer:'<path d="M14 14.8V5a2 2 0 0 0-4 0v9.8a4 4 0 1 0 4 0Z"/><path d="M12 9v7"/>',
    scale:'<path d="M12 4a4 4 0 0 0-4 4c0 2.5 4 6 4 6s4-3.5 4-6a4 4 0 0 0-4-4Z"/>',
    person:'<circle cx="12" cy="8" r="4"/><path d="M4.5 20a7.5 7.5 0 0 1 15 0"/>',
    bed:'<path d="M3 18v-8M3 14h18v4M21 18v-6a2 2 0 0 0-2-2H8"/><circle cx="7" cy="10.5" r="1.8"/>',
    shield:'<path d="M12 3 4.5 6v5.5c0 4.5 3 8 7.5 9.5 4.5-1.5 7.5-5 7.5-9.5V6Z"/><path d="m9 12 2 2 4-4"/>',
    brain:'<path d="M9.5 4.5A3 3 0 0 0 4 7a3 3 0 0 0-1 5.6A3 3 0 0 0 6 18a3 3 0 0 0 3.5 1.5Z"/><path d="M14.5 4.5A3 3 0 0 1 20 7a3 3 0 0 1 1 5.6A3 3 0 0 1 18 18a3 3 0 0 1-3.5 1.5Z"/>',
    network:'<circle cx="12" cy="5" r="2.2"/><circle cx="5" cy="18" r="2.2"/><circle cx="19" cy="18" r="2.2"/><path d="M12 7.2 6.5 16M12 7.2 17.5 16"/>',
    book:'<path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2Z"/><path d="M4 19a2 2 0 0 1 2-2h13"/>',
    question:'<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 1-1 1.7M12 16.5h.01"/>',
    doc:'<path d="M6 3h8l4 4v14H6Z"/><path d="M14 3v4h4M9 12h6M9 16h6"/>',
    camera:'<path d="M3 8.5A2.5 2.5 0 0 1 5.5 6h2L9 4h6l1.5 2h2A2.5 2.5 0 0 1 21 8.5v9A2.5 2.5 0 0 1 18.5 20h-13A2.5 2.5 0 0 1 3 17.5Z"/><circle cx="12" cy="13" r="3.5"/>',
    ellipsis:'<circle cx="5" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="19" cy="12" r="1.4" fill="currentColor" stroke="none"/>',
    calendar:'<rect x="3.5" y="5" width="17" height="16" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
    clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    check:'<path d="m5 12.5 4.5 4.5L19 7"/>',
    send:'<path d="M4 12 20 4l-6 16-2.5-6.5Z"/><path d="m11.5 13.5 8.5-9.5"/>',
    watchcase:'<rect x="7" y="6" width="10" height="12" rx="3"/><path d="M9 6V3h6v3M9 18v3h6v-3"/>'
  };
  function icon(name, opt) {
    opt = opt || {};
    const size = opt.size || 22, color = opt.color || 'currentColor', sw = opt.sw || 1.8;
    const body = P[name] || P.info;
    return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="${color}" stroke-width="${sw}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
  }
  global.ICONS = P; global.icon = icon;
})(window);
