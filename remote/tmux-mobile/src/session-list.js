export class SessionList {
  constructor(drawerEl, overlayEl, listEl, refreshBtn) {
    this.drawer = drawerEl;
    this.overlay = overlayEl;
    this.list = listEl;
    this.refreshBtn = refreshBtn;
    this.sessions = [];
    this.activeSession = null;
    this.onSelect = null;
    this.onKill = null;
    this.onCreate = null;

    this.overlay.addEventListener('click', () => this.close());
    this.refreshBtn.addEventListener('click', () => this.refresh());
  }

  async createSession() {
    try {
      const res = await fetch('/api/sessions', { method: 'POST' });
      const data = await res.json();
      if (data.ok && data.name) {
        this.activeSession = data.name;
        this.close();
        if (this.onSelect) this.onSelect(data.name);
      }
    } catch { /* ignore */ }
    await this.refresh();
  }

  open() {
    this.drawer.classList.add('open');
    this.overlay.classList.add('open');
    this.refresh();
  }

  close() {
    this.drawer.classList.remove('open');
    this.overlay.classList.remove('open');
  }

  toggle() {
    if (this.drawer.classList.contains('open')) {
      this.close();
    } else {
      this.open();
    }
  }

  async refresh() {
    try {
      const res = await fetch('/api/sessions');
      this.sessions = await res.json();
    } catch {
      this.sessions = [];
    }
    this._render();
  }

  async _killSession(name) {
    try {
      await fetch(`/api/sessions/${encodeURIComponent(name)}`, { method: 'DELETE' });
    } catch { /* ignore */ }
    await this.refresh();
    if (this.onKill) this.onKill(name);
  }

  _render() {
    this.list.innerHTML = '';

    // New session button at top
    const newBtn = document.createElement('div');
    newBtn.className = 'session-item new-session-btn';
    newBtn.innerHTML = `
      <div class="new-icon">+</div>
      <div class="info"><div class="name">New Claude Session</div></div>
    `;
    newBtn.addEventListener('click', () => this.createSession());
    this.list.appendChild(newBtn);

    if (this.sessions.length === 0) {
      this.list.insertAdjacentHTML('beforeend', '<div style="padding:20px;color:#888;text-align:center;">No tmux sessions found</div>');
      return;
    }

    // Only show alive sessions (Claude running) — dead shells are auto-cleaned
    const liveSessions = this.sessions.filter(s => s.alive);

    for (const s of liveSessions) {
      const el = document.createElement('div');
      el.className = 'session-item' + (s.name === this.activeSession ? ' active' : '');

      const ago = this._timeAgo(s.lastActivity);

      el.innerHTML = `
        <div class="dot ${s.attached ? 'attached' : ''}"></div>
        <div class="info">
          <div class="name">${this._esc(s.name)}</div>
          <div class="meta">${s.windows} window${s.windows !== 1 ? 's' : ''} · ${ago}</div>
        </div>
        <button class="kill-btn" title="Kill session">&times;</button>
      `;

      // Tap session row to connect
      el.querySelector('.info').addEventListener('click', () => {
        this.activeSession = s.name;
        this.close();
        if (this.onSelect) this.onSelect(s.name);
      });
      el.querySelector('.dot').addEventListener('click', () => {
        this.activeSession = s.name;
        this.close();
        if (this.onSelect) this.onSelect(s.name);
      });

      // Tap X to kill
      el.querySelector('.kill-btn').addEventListener('click', (e) => {
        e.stopPropagation();
        this._killSession(s.name);
      });

      this.list.appendChild(el);
    }
  }

  _timeAgo(unixTs) {
    const diff = Math.floor(Date.now() / 1000) - unixTs;
    if (diff < 60) return 'just now';
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
  }

  _esc(str) {
    const d = document.createElement('div');
    d.textContent = str;
    return d.innerHTML;
  }
}
