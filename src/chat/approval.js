(function (global) {
  'use strict';

  // Cards that need the user's answer inside the chat: IDE change approvals (diff + 승인/거부) and
  // submitted plans (진행 / 수정). chat.js owns turns and passes messages in.
  let ctx = null;
  const cards = new Map();

  function el(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function button(text, cls, onClick) {
    const b = el('button', 'card-btn ' + cls, text);
    b.addEventListener('click', onClick);
    return b;
  }

  function approval(msg) {
    const wasNear = ctx.isNearBottom();
    ctx.closeAssistant();
    const card = el('div', 'action-card approval-card');
    const head = el('div', 'card-head');
    head.appendChild(el('span', 'card-title', '승인 요청'));
    head.appendChild(el('span', 'card-target', msg.target || ''));
    card.appendChild(head);
    if (msg.summary) card.appendChild(el('div', 'card-summary', msg.summary));
    const pre = el('pre', 'card-diff');
    for (const line of msg.lines || []) {
      const row = el('div', 'diff-' + line.k);
      row.textContent = (line.k === 'add' ? '+ ' : line.k === 'del' ? '- ' : '  ') + line.t;
      pre.appendChild(row);
    }
    card.appendChild(pre);
    const actions = el('div', 'card-actions');
    const status = el('span', 'card-status');
    const answer = ok => {
      actions.querySelectorAll('button').forEach(b => { b.disabled = true; });
      status.textContent = ok ? '승인 보냄…' : '거부 보냄…';
      ctx.post({ t: 'approval', id: msg.id, ok });
    };
    actions.appendChild(button('승인', 'primary', () => answer(true)));
    actions.appendChild(button('거부', '', () => answer(false)));
    actions.appendChild(status);
    card.appendChild(actions);
    ctx.ensureTurn().appendChild(card);
    cards.set(msg.id, { card, actions, status });
    ctx.newContent(wasNear);
    card.scrollIntoView({ block: 'nearest' });
  }

  function approvalResult(msg) {
    const item = cards.get(msg.id);
    if (!item) return;
    item.actions.querySelectorAll('button').forEach(b => b.remove());
    item.status.textContent = msg.ok ? '✓ 승인됨' : '✗ 거부됨';
    item.card.classList.add(msg.ok ? 'approved' : 'refused');
    cards.delete(msg.id);
  }

  function plan(msg) {
    const wasNear = ctx.isNearBottom();
    ctx.closeAssistant();
    const card = el('div', 'action-card plan-card');
    const head = el('div', 'card-head');
    head.appendChild(el('span', 'card-title', '계획서'));
    const link = el('span', 'card-target file-link', msg.name || '');
    link.title = msg.path + ' — 에디터에서 열기';
    link.addEventListener('click', () => ctx.post({ t: 'openFile', path: msg.path, line: 1 }));
    head.appendChild(link);
    card.appendChild(head);
    card.appendChild(el('div', 'plan-title', msg.title || ''));
    const list = el('ol', 'plan-steps');
    for (const step of msg.steps || []) list.appendChild(el('li', '', step));
    card.appendChild(list);
    const actions = el('div', 'card-actions');
    const status = el('span', 'card-status');
    actions.appendChild(button('이 계획대로 진행', 'primary', () => {
      actions.querySelectorAll('button').forEach(b => { b.disabled = true; });
      status.textContent = '계획 모드를 끝내고 구현을 시작합니다';
      ctx.post({ t: 'proceedPlan', path: msg.path });
    }));
    actions.appendChild(button('계획 수정', '', () => {
      global.ChatComposer.setInput('계획을 이렇게 고쳐줘: ');
    }));
    actions.appendChild(status);
    card.appendChild(actions);
    ctx.ensureTurn().appendChild(card);
    ctx.newContent(wasNear);
  }

  global.ChatCards = {
    init: c => { ctx = c; },
    approval, approvalResult, plan,
    clear: () => cards.clear()
  };
})(typeof window !== 'undefined' ? window : globalThis);
