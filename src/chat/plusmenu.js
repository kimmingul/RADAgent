(function (global) {
  'use strict';

  // The composer's + menu: files/pictures, folders, and submenus for connectors (MCP servers)
  // and plugins with on/off switches. The IDE lists them ("extensions") and applies changes.
  let menu, sub, button;
  let data = { connectors: [], plugins: [] };
  let openSub = '';

  function el(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function post(msg) { global.chatPost(msg); }

  function close() {
    menu.hidden = true;
    sub.hidden = true;
    openSub = '';
  }

  function toggleMenu() {
    if (!menu.hidden) { close(); return; }
    menu.hidden = false;
    post({ t: 'listExtensions' });
  }

  function switchRow(item, onToggle) {
    const row = el('div', 'popup-item switch-row');
    row.appendChild(el('span', 'switch-icon', item.kind === 'extension' ? '⧉' : '⊞'));
    const name = el('span', 'popup-name', item.name);
    name.title = item.detail ? item.name + ' — ' + item.detail : item.name;
    row.appendChild(name);
    const sw = el('span', 'switch' + (item.enabled ? ' on' : ''));
    sw.appendChild(el('span', 'knob'));
    row.appendChild(sw);
    row.addEventListener('click', e => {
      e.stopPropagation();
      if (global.ChatComposer.isBusy()) return;
      item.enabled = !item.enabled;
      sw.classList.toggle('on', item.enabled);
      onToggle(item);
    });
    return row;
  }

  function renderSub() {
    if (!openSub) return;
    sub.innerHTML = '';
    const isConnectors = openSub === 'connectors';
    const manage = el('div', 'popup-item', isConnectors ? '⚙ 커넥터 관리' : '⚙ 플러그인 관리');
    manage.addEventListener('click', () => { close(); post({ t: 'manageExtensions' }); });
    sub.appendChild(manage);
    sub.appendChild(el('div', 'popup-sep'));
    const items = isConnectors ? data.connectors : data.plugins;
    if (!items.length) {
      sub.appendChild(el('div', 'popup-empty', isConnectors ? '설정된 커넥터가 없습니다' : '설치된 플러그인이 없습니다'));
    }
    for (const item of items) {
      sub.appendChild(switchRow(item, it => post(isConnectors
        ? { t: 'toggleConnector', id: it.id, enabled: it.enabled }
        : { t: 'togglePlugin', id: it.id, kind: it.kind, enabled: it.enabled })));
    }
    if (!isConnectors && items.length) {
      sub.appendChild(el('div', 'popup-empty', '바꾸면 omp를 같은 세션으로 다시 시작합니다'));
    }
    const row = menu.querySelector('[data-sub="' + openSub + '"]');
    // Both popups sit above the composer; align the submenu's bottom with the chosen row.
    sub.style.bottom = 'calc(100% + ' + (6 + menu.offsetHeight - row.offsetTop - row.offsetHeight) + 'px)';
    sub.hidden = false;
    // Right of the menu when the pane is wide enough, otherwise overlapping it.
    const room = sub.parentElement.clientWidth - sub.offsetWidth;
    sub.style.left = Math.max(0, Math.min(menu.offsetWidth + 4, room)) + 'px';
  }

  function showSub(name) {
    openSub = name;
    for (const r of menu.querySelectorAll('.has-sub')) r.classList.toggle('active', r.dataset.sub === name);
    renderSub();
  }

  function setData(msg) {
    data = { connectors: msg.connectors || [], plugins: msg.plugins || [] };
    renderSub();
  }

  function wire() {
    menu = document.getElementById('plus-menu');
    sub = document.getElementById('sub-menu');
    button = document.getElementById('plus-btn');
    button.addEventListener('click', e => { e.stopPropagation(); toggleMenu(); });
    menu.addEventListener('click', e => {
      e.stopPropagation();
      const item = e.target.closest('.popup-item');
      if (!item) return;
      if (item.dataset.sub) { showSub(item.dataset.sub); return; }
      close();
      post({ t: item.dataset.action });
    });
    menu.addEventListener('mouseover', e => {
      const item = e.target.closest('.has-sub');
      if (item && item.dataset.sub !== openSub) showSub(item.dataset.sub);
    });
    sub.addEventListener('click', e => e.stopPropagation());
    document.addEventListener('click', () => { if (!menu.hidden) close(); });
    document.addEventListener('keydown', e => { if (e.key === 'Escape' && !menu.hidden) close(); });
  }

  global.ChatPlusMenu = { wire, setData, close };
})(typeof window !== 'undefined' ? window : globalThis);
