(function (global) {
  'use strict';

  // The message box and the line under it: send/stop, / command menu, input history, context
  // chips, + menu, approval mode, model, thinking level, context ring. The IDE does the work.
  const MaxHistory = 100;
  let input, sendBtn, slash;
  let commands = [];
  let files = null;
  let menuKind = '';
  let atStart = 0;
  let matches = [];
  let active = 0;
  const history = [];
  let historyIndex = -1;
  let draft = '';
  let state = { connected: false, busy: false };
  let withSelection = false;
  let selection = '';
  let attachments = [];
  function T(key, ...args) {
    return global.T ? global.T(key, ...args) : key;
  }


  function $(id) { return document.getElementById(id); }
  function post(msg) { global.chatPost(msg); }

  function autosize() {
    input.style.height = 'auto';
    input.style.height = input.scrollHeight + 'px';
  }

  function refreshSend() {
    sendBtn.classList.toggle('stop', state.busy);
    sendBtn.textContent = state.busy ? '■' : '↑';
    sendBtn.title = state.busy ? T('page.composer.stopTitle') : T('page.composer.sendTitle');
    sendBtn.disabled = state.busy ? false : !(input.value.trim().startsWith('/btw') ||
      (state.connected && (input.value.trim() || attachments.length)));
  }

  function submit() {
    let text = input.value.trim();
    // Side question: its own omp child answers, so it also goes out while the agent works.
    const btw = /^\/btw(?:\s+([\s\S]*))?$/i.exec(text);
    if (btw) {
      if (btw[1] && btw[1].trim()) post({ t: 'btw', text: btw[1].trim(), composer: true });
      else { input.value = ''; autosize(); refreshSend(); global.ChatBtw.open(); }
      return;
    }
    if ((!text && !attachments.length) || state.busy || !state.connected) return;
    if (!text) text = T('page.composer.defaultAttachmentPrompt');
    post({ t: 'submit', text, withSelection: withSelection && !!selection,
      attachments: attachments.map(a => a.path) });
  }

  // The IDE accepted the prompt: remember it and clear the box.
  function submitted() {
    const text = input.value.trim();
    if (text && history[history.length - 1] !== text) history.push(text);
    if (history.length > MaxHistory) history.shift();
    historyIndex = -1;
    input.value = '';
    withSelection = false;
    attachments = [];
    renderChips(lastContext);
    autosize();
    refreshSend();
  }

  function recall(delta) {
    if (!history.length) return false;
    if (historyIndex === -1) {
      if (delta > 0) return false;
      draft = input.value;
      historyIndex = history.length;
    }
    historyIndex += delta;
    if (historyIndex < 0) historyIndex = 0;
    if (historyIndex >= history.length) {
      historyIndex = -1;
      input.value = draft;
    } else {
      input.value = history[historyIndex];
    }
    autosize();
    refreshSend();
    return true;
  }

  // "@part" right before the caret: files of the project folder.
  function atToken() {
    const before = input.value.slice(0, input.selectionStart);
    const m = /(^|\s)@([^\s@]*)$/.exec(before);
    return m ? { start: before.length - m[2].length - 1, part: m[2].toLowerCase() } : null;
  }

  function updateSlash() {
    const text = input.value;
    const at = atToken();
    if (at) {
      if (files === null) { files = []; post({ t: 'listFiles' }); }
      menuKind = 'at';
      atStart = at.start;
      const part = at.part.replace(/\//g, '\\');
      matches = files.filter(f => f.toLowerCase().includes(part))
        .sort((a, b) => a.length - b.length).slice(0, 12).map(f => ({ name: f, description: '' }));
      renderMenu();
      return;
    }
    const m = /^\/(\S*)$/.exec(text);
    if (!m) { slash.hidden = true; return; }
    menuKind = 'slash';
    const prefix = m[1].toLowerCase();
    matches = commands.filter(c => c.name.toLowerCase().startsWith(prefix)).slice(0, 12);
    renderMenu();
  }

  function renderMenu() {
    if (!matches.length) { slash.hidden = true; return; }
    active = Math.min(active, matches.length - 1);
    slash.innerHTML = '';
    matches.forEach((c, i) => {
      const row = document.createElement('div');
      row.className = 'popup-item' + (i === active ? ' active' : '');
      row.innerHTML = '<span class="popup-name"></span><span class="popup-desc"></span>';
      row.firstChild.textContent = menuKind === 'at' ? '@' + c.name : '/' + c.name + (c.hint ? ' ' + c.hint : '');
      row.lastChild.textContent = c.description || '';
      row.addEventListener('mousedown', e => { e.preventDefault(); pick(i); });
      slash.appendChild(row);
    });
    slash.hidden = false;
  }

  function pick(i) {
    if (menuKind === 'at') {
      const after = input.value.slice(input.selectionStart);
      input.value = input.value.slice(0, atStart) + '@' + matches[i].name + ' ' + after;
      const caret = atStart + matches[i].name.length + 2;
      input.setSelectionRange(caret, caret);
      slash.hidden = true;
      input.focus();
      autosize();
      refreshSend();
      return;
    }
    input.value = '/' + matches[i].name + ' ';
    slash.hidden = true;
    input.focus();
    autosize();
    refreshSend();
  }

  function onKeyDown(e) {
    if (e.isComposing || e.keyCode === 229) return;
    if (!slash.hidden) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        active = (active + (e.key === 'ArrowDown' ? 1 : matches.length - 1)) % matches.length;
        updateSlash();
        e.preventDefault();
        return;
      }
      if (e.key === 'Enter' || e.key === 'Tab') { pick(active); e.preventDefault(); return; }
      if (e.key === 'Escape') { slash.hidden = true; e.preventDefault(); return; }
    }
    if (e.key === 'Escape') { global.ChatPlusMenu.close(); e.preventDefault(); return; }
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); submit(); return; }
    const single = !input.value.includes('\n');
    if (e.key === 'ArrowUp' && single && input.selectionStart === 0 && recall(-1)) e.preventDefault();
    else if (e.key === 'ArrowDown' && single && historyIndex !== -1 && recall(1)) e.preventDefault();
  }

  let lastContext = null;
  function renderChips(ctx) {
    lastContext = ctx;
    const chips = $('chips');
    chips.innerHTML = '';
    if (!ctx) ctx = {};
    selection = ctx.selection || '';
    if (ctx.file) {
      const file = document.createElement('span');
      file.className = 'ctx-chip';
      file.textContent = ctx.file;
      file.title = ctx.path;
      chips.appendChild(file);
    }
    if (selection) {
      const sel = document.createElement('button');
      sel.className = 'ctx-chip' + (withSelection ? ' on' : '');
      sel.textContent = (withSelection ? '✓ ' : '+ ') + T('page.composer.selectionLines', selection);
      sel.title = withSelection ? T('page.composer.selectionTitleOn') : T('page.composer.selectionTitleOff');
      sel.addEventListener('click', () => { withSelection = !withSelection; renderChips(lastContext); input.focus(); });
      chips.appendChild(sel);
    } else {
      withSelection = false;
    }
    for (const a of attachments) {
      const chip = document.createElement('span');
      chip.className = 'ctx-chip attach';
      chip.title = a.path;
      chip.textContent = (a.image ? '🖼 ' : '📎 ') + a.name;
      const x = document.createElement('span');
      x.className = 'remove';
      x.textContent = '✕';
      x.addEventListener('click', () => {
        attachments = attachments.filter(b => b !== a);
        renderChips(lastContext);
        refreshSend();
      });
      chip.appendChild(x);
      chips.appendChild(chip);
    }
    if (ctx.unsaved > 0) {
      const un = document.createElement('span');
      un.className = 'ctx-chip';
      un.textContent = T('page.composer.unsavedCount', ctx.unsaved);
      un.title = T('page.composer.unsavedTitle');
      chips.appendChild(un);
    }
  }

  function fillSelect(sel, values, current, labelFn) {
    const known = values.slice();
    if (current && !known.includes(current)) known.unshift(current);
    // Labels are translated, so a language change must rebuild the options too.
    const key = document.documentElement.lang + '\n' + known.join('\n');
    if (sel.dataset.key !== key) {
      sel.innerHTML = '';
      for (const v of known) {
        const opt = document.createElement('option');
        opt.value = v;
        opt.textContent = labelFn ? labelFn(v) : v;
        sel.appendChild(opt);
      }
      sel.dataset.key = key;
    }
    if (current) sel.value = current;
  }

  let catalog = { models: [], levels: [] };
  function status(msg) {
    state = msg;
    const idle = msg.connected && !msg.busy;
    fillSelect($('model-select'), catalog.models, msg.model, v => v.split('/').pop());
    fillSelect($('thinking-select'), catalog.levels, msg.thinking, v => T('page.composer.thinkingLevel', v));
    $('model-select').disabled = !idle;
    $('thinking-select').disabled = !idle;
    const approval = $('approval-select');
    if (msg.approval) approval.value = msg.approval;
    approval.classList.toggle('yolo', approval.value === 'yolo');
    approval.classList.toggle('plan', approval.value === 'plan');
    approval.disabled = !msg.connected;
    const pct = msg.context >= 0 ? Math.min(100, msg.context) : 0;
    $('ctx-arc').setAttribute('stroke-dasharray', (pct / 100 * 50.3).toFixed(1) + ' 50.3');
    $('ctx-ring').setAttribute('title', msg.context >= 0 ? T('page.composer.contextPct', pct.toFixed(0)) : T('page.composer.noContext'));
    const dot = $('conn-dot');
    dot.className = msg.error ? 'error' : msg.connected ? '' : 'off';
    dot.title = msg.state || '';
    refreshSend();
  }

  function setCatalog(msg) {
    catalog = { models: msg.models || [], levels: msg.levels || [] };
    status(state);
  }

  function wire() {
    input = $('input');
    sendBtn = $('send-btn');
    slash = $('slash-menu');
    input.addEventListener('input', () => { active = 0; autosize(); updateSlash(); refreshSend(); });
    input.addEventListener('click', () => updateSlash());
    input.addEventListener('keydown', onKeyDown);
    input.addEventListener('blur', () => { setTimeout(() => { slash.hidden = true; }, 150); });
    sendBtn.addEventListener('click', () => { if (state.busy) post({ t: 'abort' }); else submit(); });
    $('model-select').addEventListener('change', e => post({ t: 'setModel', value: e.target.value }));
    $('thinking-select').addEventListener('change', e => post({ t: 'setThinking', value: e.target.value }));
    $('approval-select').addEventListener('change', e => post({ t: 'setApproval', value: e.target.value }));
    input.focus();
  }

  function setInput(text) { input.value = text || ''; autosize(); refreshSend(); input.focus(); }

  function insertText(text) {
    const at = input.selectionStart;
    const before = input.value.slice(0, at);
    const sep = before && !/\s$/.test(before) ? ' ' : '';
    input.value = before + sep + text + input.value.slice(input.selectionEnd);
    autosize();
    refreshSend();
    input.focus();
  }

  function addAttachments(items) {
    for (const it of items || []) {
      if (!attachments.some(a => a.path === it.path)) attachments.push(it);
    }
    renderChips(lastContext);
    refreshSend();
    input.focus();
  }

  global.ChatComposer = {
    wire, status, setCatalog, submitted, setInput, insertText, addAttachments,
    isBusy: () => !!state.busy || !state.connected,
    context: renderChips,
    commands: items => { commands = Array.isArray(items) ? items : []; },
    files: items => { files = Array.isArray(items) ? items : []; if (menuKind === 'at') updateSlash(); },
    focus: () => input && input.focus()
  };
})(typeof window !== 'undefined' ? window : globalThis);
