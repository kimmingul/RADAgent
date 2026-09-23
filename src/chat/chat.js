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

  let logEl = null;
  let scrollBtn = null;
  let currentTurn = null;
  let currentAssistantBlock = null;
  let currentAssistantText = '';
  let rafPending = false;
  const activeTools = new Map();

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
      currentTurn = document.createElement('div');
      currentTurn.className = 'turn turn-assistant';

      const header = document.createElement('div');
      header.className = 'assistant-header';
      header.textContent = 'omp';
      currentTurn.appendChild(header);
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
    const header = document.createElement('div');
    header.className = 'user-header';
    header.textContent = '나';
    const body = document.createElement('div');
    body.className = 'user-text';
    body.textContent = text || '';

    bubble.appendChild(header);
    bubble.appendChild(body);
    turn.appendChild(bubble);
    logEl.appendChild(turn);
    handleNewContent(wasNear);
  }

  function handleAssistantDelta(text) {
    const wasNear = isNearBottom();
    const turn = ensureAssistantTurn();

    if (!currentAssistantBlock) {
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

  function handleToolStart(id, name, detail, input) {
    const wasNear = isNearBottom();
    closeAssistantBlock();
    const turn = ensureAssistantTurn();

    const row = document.createElement('details');
    row.className = 'tool-row running';
    row.id = 'tool-' + id;
    const summary = document.createElement('summary');
    summary.className = 'tool-summary';

    const iconSpan = document.createElement('span');
    iconSpan.className = 'tool-status-icon';
    const spinner = document.createElement('span');
    spinner.className = 'tool-spinner';
    iconSpan.appendChild(spinner);

    const nameSpan = document.createElement('span');
    nameSpan.className = 'tool-name';
    nameSpan.textContent = name;
    const detailSpan = document.createElement('span');
    detailSpan.className = 'tool-detail';
    detailSpan.textContent = detail || '';
    const metaSpan = document.createElement('span');
    metaSpan.className = 'tool-meta';

    summary.appendChild(iconSpan);
    summary.appendChild(nameSpan);
    summary.appendChild(detailSpan);
    summary.appendChild(metaSpan);

    const resultPre = document.createElement('pre');
    resultPre.className = 'tool-result';
    row.appendChild(summary);
    row.appendChild(resultPre);
    global.ChatActivity.attachInput(row, resultPre, input || global.ChatActivity.takeDraft(id));
    turn.appendChild(row);

    activeTools.set(id, { row, iconSpan, metaSpan, resultPre });
    handleNewContent(wasNear);
  }

  function formatDuration(ms) {
    if (typeof ms !== 'number' || ms < 0) return '';
    if (ms >= 10000) return Math.round(ms / 1000) + '초';
    return (ms / 1000).toFixed(1) + '초';
  }

  function handleToolEnd(id, ok, ms, result) {
    const wasNear = isNearBottom();
    const tool = activeTools.get(id) || (function () {
      const row = document.getElementById('tool-' + id);
      if (!row) return null;
      return {
        row: row,
        iconSpan: row.querySelector('.tool-status-icon'),
        metaSpan: row.querySelector('.tool-meta'),
        resultPre: row.querySelector('.tool-result')
      };
    })();

    if (tool) {
      tool.row.classList.remove('running');
      if (tool.iconSpan) {
        tool.iconSpan.innerHTML = ok
          ? '<span class="tool-ok">✓</span>'
          : '<span class="tool-err">✗</span>';
      }
      if (tool.metaSpan) {
        tool.metaSpan.textContent = formatDuration(ms);
      }
      if (tool.resultPre) {
        const text = result || '';
        const lines = text.split('\n');
        let display = text;
        if (lines.length > 200) {
          const shown = lines.slice(0, 200).join('\n');
          const remaining = lines.length - 200;
          display = shown + '\n\n… (' + remaining + '줄 더)';
        }
        tool.resultPre.innerHTML = global.Markdown.linkFileRefs(global.Markdown.escapeHtml(display));
      }
      activeTools.delete(id);
    }
    handleNewContent(wasNear);
  }

  function handleNotice(level, text) {
    const wasNear = isNearBottom();
    const notice = document.createElement('div');
    notice.className = 'notice notice-' + (level || 'info');
    notice.textContent = text || '';
    logEl.appendChild(notice);
    handleNewContent(wasNear);
  }

  function handleTurnEnd() {
    closeAssistantBlock();
    global.ChatActivity.endTurn();
    for (const [, tool] of activeTools.entries()) {
      if (tool.iconSpan) tool.iconSpan.innerHTML = '<span class="tool-warn">!</span>';
      if (tool.metaSpan) tool.metaSpan.textContent = '중단됨';
    }
    activeTools.clear();
    currentTurn = null;
  }

  function handleClear() {
    if (logEl) logEl.innerHTML = '';
    currentTurn = null;
    closeAssistantBlock();
    activeTools.clear();
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
        const header = document.createElement('div');
        header.className = 'user-header';
        header.textContent = '나';
        const body = document.createElement('div');
        body.className = 'user-text';
        body.textContent = item.text || '';
        bubble.appendChild(header);
        bubble.appendChild(body);
        turn.appendChild(bubble);
        logEl.appendChild(turn);
      } else {
        const turn = document.createElement('div');
        turn.className = 'turn turn-assistant';
        const header = document.createElement('div');
        header.className = 'assistant-header';
        header.textContent = 'omp';
        turn.appendChild(header);
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
      case 'theme': handleTheme(msg.vars); break;
      case 'user': handleUser(msg.text); break;
      case 'assistantDelta': handleAssistantDelta(msg.text); break;
      case 'assistantEnd': handleAssistantEnd(); break;
      case 'toolStart': handleToolStart(msg.id, msg.name, msg.detail, msg.input); break;
      case 'toolInputDelta': global.ChatActivity.toolInputDelta(msg.id, msg.name, msg.text); break;
      case 'toolUpdate': global.ChatActivity.toolUpdate(activeTools.get(msg.id), msg.text); break;
      case 'thinkingDelta': global.ChatActivity.thinkingDelta(msg.text); break;
      case 'thinkingEnd': global.ChatActivity.thinkingEnd(); break;
      case 'thinking': global.ChatActivity.thinkingBlock(msg.text); break;
      case 'subagent': global.ChatActivity.subagent(msg); break;
      case 'todos': global.ChatActivity.todos(msg.items); break;
      case 'display': global.ChatActivity.display(msg.show); break;
      case 'toolEnd': handleToolEnd(msg.id, msg.ok, msg.ms, msg.result); break;
      case 'notice': handleNotice(msg.level, msg.text); break;
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
      copyBtn.textContent = '복사됨';
      setTimeout(() => { copyBtn.textContent = '복사'; }, 1500);
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
    logEl = document.getElementById('log');
    global.ChatActivity.init({
      isNearBottom, newContent: handleNewContent, ensureTurn: ensureAssistantTurn,
      closeAssistant: closeAssistantBlock
    });
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
    postHost({ t: 'ready' });
  });

  if (global.chrome?.webview) {
    global.chrome.webview.addEventListener('message', e => handle(e.data));
  }
  global.__agentHost = handle;

})(typeof window !== 'undefined' ? window : globalThis);
