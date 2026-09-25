(function (global) {
  'use strict';

  global.__outbox = global.__outbox || [];

  function postHost(msg) {
    if (global.chrome?.webview?.postMessage) {
      global.chrome.webview.postMessage(msg);
    } else {
      global.__outbox.push(msg);
    }
  }
  let stringDict = {};

  const has = key => Object.prototype.hasOwnProperty.call(stringDict, key);
  // "<key>.one" is the wording for a first value of 1 ("1 tool used" against "{0} tools used").
  global.T = function (key, ...args) {
    if (args.length > 0 && Number(args[0]) === 1 && has(key + '.one')) key += '.one';
    let str = has(key) ? stringDict[key] : key;
    if (args.length > 0) {
      args.forEach((arg, i) => {
        str = str.split('{' + i + '}').join(arg);
      });
    }
    return str;
  };

  function applyStrings() {
    if (typeof document === 'undefined') return;
    document.querySelectorAll('[data-i18n]').forEach(el => {
      el.textContent = global.T(el.getAttribute('data-i18n'));
    });
    document.querySelectorAll('[data-i18n-title]').forEach(el => {
      el.setAttribute('title', global.T(el.getAttribute('data-i18n-title')));
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
      el.setAttribute('placeholder', global.T(el.getAttribute('data-i18n-placeholder')));
    });
    document.querySelectorAll('[data-i18n-aria-label]').forEach(el => {
      el.setAttribute('aria-label', global.T(el.getAttribute('data-i18n-aria-label')));
    });
  }

  function handleStrings(msg) {
    if (msg.items && typeof msg.items === 'object') {
      stringDict = msg.items;
    }
    if (msg.lang && document.documentElement) {
      document.documentElement.lang = msg.lang;
    }
    applyStrings();
  }


  let logEl = null;
  let scrollBtn = null;
  let currentTurn = null;
  let currentAssistantBlock = null;
  let currentAssistantText = '';
  let rafPending = false;

  function isNearBottom() {
    if (!logEl) return true;
    return (logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight) <= 60;
  }

  function scrollToBottom(smooth) {
    if (!logEl) return;
    if (smooth) {
      logEl.scrollTo({ top: logEl.scrollHeight, behavior: 'smooth' });
    } else {
      logEl.scrollTop = logEl.scrollHeight;
    }
    if (scrollBtn) scrollBtn.classList.remove('visible');
  }

  function handleNewContent(wasNearBottom) {
    if (wasNearBottom) {
      scrollToBottom(false);
    } else {
      if (scrollBtn) scrollBtn.classList.add('visible');
    }
  }

  function flushAssistantBlock() {
    rafPending = false;
    if (currentAssistantBlock && currentAssistantText) {
      currentAssistantBlock.innerHTML = global.Markdown.render(currentAssistantText);
    }
  }

  function closeAssistantBlock() {
    flushAssistantBlock();
    currentAssistantBlock = null;
    currentAssistantText = '';
  }

  function ensureAssistantTurn() {
    if (!currentTurn || !currentTurn.classList.contains('turn-assistant')) {
      closeAssistantBlock();
      global.ChatTools.endGroup();
      currentTurn = document.createElement('div');
      currentTurn.className = 'turn turn-assistant';
      logEl.appendChild(currentTurn);
    }
    return currentTurn;
  }

  function handleTheme(vars) {
    if (!vars) return;
    const root = document.documentElement;
    for (const [key, val] of Object.entries(vars)) {
      let cssVal = val;
      if (key === 'fontSize' && typeof val === 'number') {
        cssVal = val + 'px';
      }
      root.style.setProperty('--' + key, cssVal);
    }
  }

  function handleUser(text) {
    const wasNear = isNearBottom();
    closeAssistantBlock();
    currentTurn = null;

    const turn = document.createElement('div');
    turn.className = 'turn turn-user';
    const bubble = document.createElement('div');
    bubble.className = 'user-bubble';
    const body = document.createElement('div');
    body.className = 'user-text';
    body.textContent = text || '';
    bubble.appendChild(body);
    turn.appendChild(bubble);
    logEl.appendChild(turn);
    handleNewContent(wasNear);
  }

  function handleAssistantDelta(text) {
    const wasNear = isNearBottom();
    const turn = ensureAssistantTurn();

    if (!currentAssistantBlock) {
      // Answer text ends the current tool group; later tools start a new one.
      global.ChatTools.endGroup();
      const bubble = document.createElement('div');
      bubble.className = 'assistant-bubble';
      const body = document.createElement('div');
      body.className = 'markdown-body';
      bubble.appendChild(body);
      turn.appendChild(bubble);
      currentAssistantBlock = body;
      currentAssistantText = '';
    }

    currentAssistantText += text;

    if (!rafPending) {
      rafPending = true;
      requestAnimationFrame(() => {
        if (!rafPending) return;
        rafPending = false;
        if (currentAssistantBlock) {
          currentAssistantBlock.innerHTML = global.Markdown.render(currentAssistantText);
          handleNewContent(wasNear);
        }
      });
    }
  }

  function handleAssistantEnd() {
    closeAssistantBlock();
  }

  // Model names in the text (fallback "a/x → b/y") get their logo in front.
  function handleNotice(level, text, models) {
    const wasNear = isNearBottom();
    // Output of a slash command omp ran itself: keep its layout.
    const notice = document.createElement(level === 'output' ? 'pre' : 'div');
    notice.className = 'notice notice-' + (level || 'info');
    appendWithLogos(notice, text || '', Array.isArray(models) ? models.filter(Boolean) : []);
    logEl.appendChild(notice);
    handleNewContent(wasNear);
  }

  function appendWithLogos(parent, text, models) {
    let rest = text;
    while (models.length) {
      let at = -1, found = '';
      for (const m of models) {
        const i = rest.indexOf(m);
        if (i >= 0 && (at < 0 || i < at)) { at = i; found = m; }
      }
      if (at < 0) break;
      parent.appendChild(document.createTextNode(rest.slice(0, at)));
      parent.appendChild(global.ChatBrands.modelIcon(found));
      parent.appendChild(document.createTextNode(found));
      rest = rest.slice(at + found.length);
    }
    parent.appendChild(document.createTextNode(rest));
  }

  // Which model answers from here on: shown when it differs from the previous answer's model.
  let lastModel = '';
  function modelTag(selector) {
    lastModel = selector;
    const tag = document.createElement('div');
    tag.className = 'model-tag';
    tag.title = selector;
    tag.appendChild(global.ChatBrands.modelIcon(selector));
    const name = document.createElement('span');
    name.textContent = global.ChatBrands.split(selector).model;
    tag.appendChild(name);
    return tag;
  }

  function handleModel(selector) {
    if (!selector || selector === lastModel) return;
    closeAssistantBlock();
    const wasNear = isNearBottom();
    ensureAssistantTurn().appendChild(modelTag(selector));
    handleNewContent(wasNear);
  }

  function handleTurnEnd() {
    closeAssistantBlock();
    global.ChatActivity.endTurn();
    global.ChatTools.endTurn();
    currentTurn = null;
  }

  function handleClear() {
    if (logEl) logEl.innerHTML = '';
    lastModel = '';
    currentTurn = null;
    closeAssistantBlock();
    global.ChatTools.clear();
    global.ChatCards.clear();
    global.ChatBtw.clear();
    global.ChatActivity.clear();
    if (scrollBtn) scrollBtn.classList.remove('visible');
  }

  function handleHistory(items) {
    handleClear();
    if (!Array.isArray(items)) return;

    for (const item of items) {
      if (!item) continue;
      if (item.role === 'user') {
        const turn = document.createElement('div');
        turn.className = 'turn turn-user';
        const bubble = document.createElement('div');
        bubble.className = 'user-bubble';
        const body = document.createElement('div');
        body.className = 'user-text';
        body.textContent = item.text || '';
        bubble.appendChild(body);
        turn.appendChild(bubble);
        logEl.appendChild(turn);
      } else {
        if (item.model && item.model !== lastModel) logEl.appendChild(modelTag(item.model));
        const turn = document.createElement('div');
        turn.className = 'turn turn-assistant';
        const bubble = document.createElement('div');
        bubble.className = 'assistant-bubble';
        const body = document.createElement('div');
        body.className = 'markdown-body';
        body.innerHTML = global.Markdown.render(item.text || '');
        bubble.appendChild(body);
        turn.appendChild(bubble);
        logEl.appendChild(turn);
      }
    }
    scrollToBottom(false);
  }

  function handle(msg) {
    if (!msg || typeof msg !== 'object') return;
    switch (msg.t) {
      case 'strings': handleStrings(msg); if (global.ChatModelPicker && logEl) global.ChatModelPicker.relabel(); break;
      case 'theme': handleTheme(msg.vars); break;
      case 'user': handleUser(msg.text); break;
      case 'assistantDelta': handleAssistantDelta(msg.text); break;
      case 'assistantEnd': handleAssistantEnd(); break;
      case 'toolStart': global.ChatTools.start(msg.id, msg.name, msg.detail, msg.input); break;
      case 'toolEnd': global.ChatTools.end(msg.id, msg.ok, msg.ms, msg.result); break;
      case 'fileChange': global.ChatTools.fileChange(msg); break;
      case 'status': global.ChatTopbar.status(msg); global.ChatComposer.status(msg); break;
      case 'catalog': global.ChatComposer.setCatalog(msg); break;
      case 'context': global.ChatComposer.context(msg); break;
      case 'commands': global.ChatComposer.commands(msg.items); break;
      case 'submitted': global.ChatComposer.submitted(); break;
      case 'setInput': global.ChatComposer.setInput(msg.text); break;
      case 'insertText': global.ChatComposer.insertText(msg.text); break;
      case 'attachments': global.ChatComposer.addAttachments(msg.items); break;
      case 'extensions': global.ChatPlusMenu.setData(msg); break;
      case 'files': global.ChatComposer.files(msg.items); break;
      case 'approval': global.ChatCards.approval(msg); break;
      case 'approvalResult': global.ChatCards.approvalResult(msg); break;
      case 'plan': global.ChatCards.plan(msg); break;
      case 'btw': global.ChatBtw.update(msg); break;
      case 'checkpoint': global.ChatCheckpoints.one(msg); break;
      case 'checkpoints': global.ChatCheckpoints.list(msg); break;
      case 'btwList': global.ChatBtw.setList(msg); break;
      case 'focusInput': global.ChatComposer.focus(); break;
      case 'toolInputDelta': global.ChatActivity.toolInputDelta(msg.id, msg.name, msg.text); break;
      case 'toolUpdate': global.ChatTools.update(msg.id, msg.text); break;
      case 'thinkingDelta': global.ChatActivity.thinkingDelta(msg.text); break;
      case 'thinkingEnd': global.ChatActivity.thinkingEnd(); break;
      case 'thinking': global.ChatActivity.thinkingBlock(msg.text); break;
      case 'subagent': global.ChatActivity.subagent(msg); break;
      case 'todos': global.ChatActivity.todos(msg.items); break;
      case 'display': global.ChatActivity.display(msg.show); break;
      case 'notice': handleNotice(msg.level, msg.text, msg.models); break;
      case 'model': handleModel(msg.model); break;
      case 'turnEnd': handleTurnEnd(); break;
      case 'clear': handleClear(); break;
      case 'history': handleHistory(msg.items); break;
    }
  }

  // Click delegation
  document.addEventListener('click', (e) => {
    const fileRef = e.target.closest('.file-ref');
    if (fileRef) {
      e.preventDefault();
      e.stopPropagation();
      postHost({
        t: 'openFile',
        path: fileRef.getAttribute('data-path') || '',
        line: parseInt(fileRef.getAttribute('data-line') || '0', 10)
      });
      return;
    }

    const copyBtn = e.target.closest('.code-copy-btn');
    if (copyBtn) {
      e.preventDefault();
      e.stopPropagation();
      const code = copyBtn.getAttribute('data-code') || '';
      if (navigator.clipboard?.writeText) {
        navigator.clipboard.writeText(code).catch(() => {});
      }
      postHost({ t: 'copy', text: code });
      copyBtn.textContent = global.T('page.chat.copied');
      setTimeout(() => { copyBtn.textContent = global.T('page.chat.copy'); }, 1500);
      return;
    }

    const link = e.target.closest('.chat-link');
    if (link) {
      e.preventDefault();
      e.stopPropagation();
      postHost({
        t: 'openUrl',
        url: link.getAttribute('data-url') || ''
      });
      return;
    }
  });

  window.addEventListener('DOMContentLoaded', () => {
    applyStrings();
    logEl = document.getElementById('log');
    const ctx = {
      isNearBottom, newContent: handleNewContent, ensureTurn: ensureAssistantTurn,
      closeAssistant: closeAssistantBlock, post: postHost,
      ensureGroup: (kind, id) => global.ChatTools.ensureGroup(kind, id),
      // Outside the current turn, above the working line: the turn keeps streaming above it.
      appendLog: node => {
        const working = document.getElementById('working');
        if (working && logEl.lastElementChild === working && !working.hidden) logEl.insertBefore(node, working);
        else logEl.appendChild(node);
      }
    };
    global.ChatTools.init(ctx);
    global.ChatCards.init(ctx);
    global.ChatActivity.init(ctx);
    global.ChatTopbar.wire();
    global.ChatModelPicker.wire();
    global.ChatComposer.wire();
    global.ChatPlusMenu.wire();
    global.ChatBtw.wire(ctx);
    global.ChatCheckpoints.init(postHost);
    scrollBtn = document.getElementById('scroll-bottom-btn');
    if (scrollBtn) {
      scrollBtn.addEventListener('click', () => scrollToBottom(true));
    }
    if (logEl) {
      logEl.addEventListener('scroll', () => {
        if (isNearBottom() && scrollBtn) {
          scrollBtn.classList.remove('visible');
        }
      });
    }
    // Logos are resolved while messages render, so the rule table comes first.
    global.ChatBrands.load().then(() => {
      brandsReady = true;
      pending.splice(0).forEach(handle);
      postHost({ t: 'ready' });
    });
  });

  let brandsReady = false;
  const pending = [];
  function receive(msg) { if (brandsReady) handle(msg); else pending.push(msg); }
  if (global.chrome?.webview) {
    global.chrome.webview.addEventListener('message', e => receive(e.data));
  }
  global.__agentHost = receive;
  global.chatPost = postHost;
  global.ChatView = { isNearBottom, newContent: handleNewContent };

})(typeof window !== 'undefined' ? window : globalThis);
