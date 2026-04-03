import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { WebLinksAddon } from '@xterm/addon-web-links';

export class TerminalView {
  constructor(container) {
    this.container = container;
    this.ws = null;
    this.term = null;
    this.fitAddon = null;
    this.onConnect = null;
    this.onDisconnect = null;
    this.onRename = null;
    this._resizeObserver = null;
    this._currentSession = null;

    this._init();
  }

  _init() {
    this.term = new Terminal({
      fontSize: 13,
      fontFamily: "'Cascadia Code', 'Fira Code', 'Menlo', monospace",
      theme: {
        background: '#1a1a2e',
        foreground: '#e0e0e0',
        cursor: '#4ecca3',
        selectionBackground: 'rgba(78, 204, 163, 0.3)',
      },
      cursorBlink: true,
      scrollback: 5000,
      convertEol: true,
      allowProposedApi: true,
    });

    this.fitAddon = new FitAddon();
    this.term.loadAddon(this.fitAddon);
    this.term.loadAddon(new WebLinksAddon({
      handler: (_event, uri) => {
        window.open(uri, '_blank');
      },
    }));

    this.term.open(this.container);
    this.fitAddon.fit();

    // Touch gestures: scroll (vertical) and swipe-right (accept suggestion)
    this._touchStartX = 0;
    this._touchStartY = 0;
    this._lastTouchY = 0;
    this._scrollAccum = 0;
    this._gestureDecided = false;
    this._gestureIsScroll = false;

    // Long press to select all + copy
    this._longPressTimer = null;

    this.container.addEventListener('touchstart', (e) => {
      if (e.touches.length === 1) {
        this._touchStartX = e.touches[0].clientX;
        this._touchStartY = e.touches[0].clientY;
        this._lastTouchY = e.touches[0].clientY;
        this._scrollAccum = 0;
        this._gestureDecided = false;
        this._gestureIsScroll = false;

        // Start long press timer
        this._longPressTimer = setTimeout(() => {
          this._longPressTimer = null;
          this._gestureDecided = true; // prevent scroll/swipe
          this._showSelectOverlay();
        }, 1000);
      }
    }, { passive: true });

    this.container.addEventListener('touchmove', (e) => {
      if (e.touches.length !== 1) return;
      const curY = e.touches[0].clientY;
      const dx = e.touches[0].clientX - this._touchStartX;
      const dyFromStart = this._touchStartY - curY;

      // Cancel long press if finger moves
      if (this._longPressTimer && (Math.abs(dx) > 10 || Math.abs(dyFromStart) > 10)) {
        clearTimeout(this._longPressTimer);
        this._longPressTimer = null;
      }

      // Decide gesture direction on first significant movement
      if (!this._gestureDecided && (Math.abs(dx) > 15 || Math.abs(dyFromStart) > 15)) {
        this._gestureDecided = true;
        this._gestureIsScroll = Math.abs(dyFromStart) >= Math.abs(dx);
        if (this._gestureIsScroll) {
          // Reset baseline so first scroll delta is near zero (no sudden jump)
          this._lastTouchY = curY;
          this._scrollAccum = 0;
        }
      }

      if (!this._gestureDecided) return;

      if (this._gestureIsScroll) {
        const delta = this._lastTouchY - curY;
        this._lastTouchY = curY;

        const pxPerLine = 22;
        this._scrollAccum += delta;
        const lines = Math.trunc(this._scrollAccum / pxPerLine);
        if (lines !== 0) {
          const btn = lines > 0 ? 65 : 64;
          const count = Math.abs(lines);
          for (let i = 0; i < count; i++) {
            this._send({ type: 'input', data: `\x1b[<${btn};1;1M` });
          }
          this._scrollAccum -= lines * pxPerLine;
        }
      }
    }, { passive: true });

    this.container.addEventListener('touchend', (e) => {
      if (this._longPressTimer) {
        clearTimeout(this._longPressTimer);
        this._longPressTimer = null;
      }

      // Quick tap (no gesture decided): check if tapped on a link
      if (!this._gestureDecided && e.changedTouches.length === 1) {
        const touch = e.changedTouches[0];
        const dx = Math.abs(touch.clientX - this._touchStartX);
        const dy = Math.abs(touch.clientY - this._touchStartY);
        if (dx < 25 && dy < 25) {
          this._handleLinkTap(touch.clientX, touch.clientY);
        }
        return;
      }

      if (!this._gestureDecided) return;
      if (!this._gestureIsScroll) {
        // Horizontal gesture completed: check if it was a swipe right
        const dx = e.changedTouches[0].clientX - this._touchStartX;
        if (dx > 60) {
          // Swipe right: send Right arrow key (accept Claude Code suggestion)
          this._send({ type: 'input', data: '\x1b[C' });
        }
      }
    }, { passive: true });

    // Resize on container size change
    this._resizeObserver = new ResizeObserver(() => {
      this.fitAddon.fit();
      this._sendResize();
    });
    this._resizeObserver.observe(this.container);

    // Forward terminal input to WebSocket
    this.term.onData(data => {
      this._send({ type: 'input', data });
    });
  }

  connect(sessionName) {
    const isReconnect = this._currentSession === sessionName;
    this._currentSession = sessionName;
    this.disconnect();

    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const url = `${proto}//${location.host}/ws/terminal/${encodeURIComponent(sessionName)}`;
    this.ws = new WebSocket(url);

    this.ws.onopen = () => {
      if (!isReconnect) {
        this.term.clear();
      }
      this.fitAddon.fit();
      this._sendResize();
      if (this.onConnect) this.onConnect();
    };

    this.ws.onmessage = (evt) => {
      if (typeof evt.data === 'string') {
        // Check for control messages from server
        if (evt.data.charAt(0) === '{') {
          try {
            const msg = JSON.parse(evt.data);
            if (msg.type === 'sessionRenamed' && this.onRename) {
              this._currentSession = msg.name;
              this.onRename(msg.name);
              return;
            }
          } catch { /* not JSON, treat as terminal data */ }
        }
        this.term.write(evt.data);
      } else {
        this.term.write(new Uint8Array(evt.data));
      }
    };

    this.ws.onclose = () => {
      if (this.onDisconnect) this.onDisconnect();
    };

    this.ws.onerror = () => {
      if (this.onDisconnect) this.onDisconnect();
    };
  }

  disconnect() {
    if (this.ws) {
      this.ws.onclose = null;
      this.ws.onerror = null;
      this.ws.close();
      this.ws = null;
    }
  }

  sendText(text) {
    this._send({ type: 'input', data: text });
  }

  _handleLinkTap(x, y) {
    // Convert screen coordinates to terminal cell position
    const screen = this.container.querySelector('.xterm-screen');
    if (!screen) return;
    const rect = screen.getBoundingClientRect();

    const cellWidth = rect.width / this.term.cols;
    const cellHeight = rect.height / this.term.rows;

    const col = Math.floor((x - rect.left) / cellWidth);
    const row = Math.floor((y - rect.top) / cellHeight);

    if (col < 0 || col >= this.term.cols || row < 0 || row >= this.term.rows) return;

    // Check this row and adjacent rows (links can wrap)
    const buf = this.term.buffer.active;
    const rowsToCheck = [row - 1, row, row + 1];
    const urlRegex = /https?:\/\/[^\s<>"{}|\\^`()\[\]]+/g;

    for (const r of rowsToCheck) {
      if (r < 0 || r >= this.term.rows) continue;
      const line = buf.getLine(buf.viewportY + r);
      if (!line) continue;
      const text = line.translateToString(false);

      let match;
      while ((match = urlRegex.exec(text)) !== null) {
        if (r === row) {
          const start = match.index;
          const end = start + match[0].length;
          if (col >= start - 1 && col <= end) {
            let url = match[0].replace(/[.,;:!?)]+$/, '');
            if (navigator.vibrate) navigator.vibrate(50);
            window.open(url, '_blank');
            return;
          }
        }
      }
      urlRegex.lastIndex = 0;
    }
  }

  _showSelectOverlay() {
    // Extract visible terminal text from the buffer
    const buf = this.term.buffer.active;
    const lines = [];
    for (let i = 0; i < this.term.rows; i++) {
      const line = buf.getLine(buf.viewportY + i);
      if (line) lines.push(line.translateToString(true));
    }
    const text = lines.join('\n');

    // Create overlay with real selectable DOM text
    const overlay = document.createElement('div');
    overlay.className = 'select-overlay';

    const closeBtn = document.createElement('button');
    closeBtn.className = 'select-overlay-close';
    closeBtn.textContent = 'Done';
    closeBtn.addEventListener('click', () => overlay.remove());

    const content = document.createElement('pre');
    content.className = 'select-overlay-text';
    content.textContent = text;

    const hint = document.createElement('div');
    hint.className = 'select-overlay-hint';
    hint.textContent = 'Long press text to select';

    overlay.appendChild(closeBtn);
    overlay.appendChild(hint);
    overlay.appendChild(content);
    document.body.appendChild(overlay);
  }

  scrollToBottom() {
    this.term.scrollToBottom();
  }

  _send(obj) {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(obj));
    }
  }

  _sendResize() {
    this._send({ type: 'resize', cols: this.term.cols, rows: this.term.rows });
  }

  destroy() {
    this.disconnect();
    if (this._resizeObserver) this._resizeObserver.disconnect();
    this.term.dispose();
  }
}
