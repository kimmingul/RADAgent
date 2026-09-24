(function (global) {
  'use strict';

  // Every user message has a git checkpoint of the project just before it (IDE side). Hovering a
  // message offers going back to that state (files and conversation) or a git branch from there.
  let post = null;

  function actions(turn, seq) {
    if (!turn || turn.querySelector('.cp-actions')) return;
    turn.dataset.seq = String(seq);
    const bar = document.createElement('div');
    bar.className = 'cp-actions';
    const add = (label, title, branch) => {
      const b = document.createElement('button');
      b.className = 'cp-btn';
      b.textContent = label;
      b.title = title;
      b.addEventListener('click', () => post({ t: 'restore', seq, branch }));
      bar.appendChild(b);
    };
    add('↶ 여기로 되돌리기', '이 메시지를 보내기 전 상태로 파일과 대화를 되돌립니다', false);
    add('⑂ 여기서 브랜치', '이 메시지를 보내기 전 상태에서 새 git 브랜치를 만듭니다', true);
    turn.appendChild(bar);
  }

  // The message just shown.
  function one(msg) {
    const turns = document.querySelectorAll('#log .turn-user');
    actions(turns[turns.length - 1], msg.seq);
  }

  function text(turn) {
    const body = turn.querySelector('.user-text');
    return body ? body.textContent.trim() : '';
  }

  // A reloaded history: match messages to checkpoints from the newest back, by text.
  function list(msg) {
    const points = (msg.items || []).slice();
    const turns = [...document.querySelectorAll('#log .turn-user')].filter(t => !t.dataset.seq);
    let limit = Infinity;
    for (let i = turns.length - 1; i >= 0; i--) {
      const shown = text(turns[i]);
      if (!shown) continue;
      for (let k = points.length - 1; k >= 0; k--) {
        const p = points[k];
        if (p.seq >= limit) continue;
        const prompt = (p.prompt || '').trim();
        if (prompt === shown || prompt.startsWith(shown) || shown.startsWith(prompt)) {
          actions(turns[i], p.seq);
          limit = p.seq;
          points.splice(k, 1);
          break;
        }
      }
    }
  }

  global.ChatCheckpoints = { init: p => { post = p; }, one, list };
})(typeof window !== 'undefined' ? window : globalThis);
