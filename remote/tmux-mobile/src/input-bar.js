export class InputBar {
  constructor(inputEl, sendBtn) {
    this.input = inputEl;
    this.sendBtn = sendBtn;
    this.onSend = null;

    this.sendBtn.addEventListener('click', () => this._handleSend());

    this.input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        e.preventDefault();
        this._handleSend();
      }
    });
  }

  _handleSend() {
    const text = this.input.value;
    if (!text) {
      // Empty input: send Enter to the terminal (e.g. to execute an accepted suggestion)
      if (this.onSend) this.onSend('\r');
      return;
    }
    this.input.value = '';
    if (this.onSend) {
      this.onSend(text);
      setTimeout(() => this.onSend('\r'), 100);
    }
    this.input.focus();
  }

  focus() {
    this.input.focus();
  }
}
