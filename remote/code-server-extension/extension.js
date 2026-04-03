const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const HOME = process.env.HOME || '/home/user';
const SNOOZE_DIR = path.join(HOME, '.claude', 'snooze-active');

// Track terminals we opened this session, so we can distinguish
// "user closed tab" from "code-server reloaded" (which also fires onDidCloseTerminal)
const ourTerminals = new Set();

function activate(context) {
  console.log('[claude-snooze] Extension activated (persistent marker mode)');

  // When user closes a terminal tab we created, delete the marker so it won't re-open
  context.subscriptions.push(
    vscode.window.onDidCloseTerminal(terminal => {
      if (ourTerminals.has(terminal.name)) {
        ourTerminals.delete(terminal.name);
        const marker = path.join(SNOOZE_DIR, terminal.name);
        try { fs.unlinkSync(marker); } catch (e) {}
        console.log('[claude-snooze] User closed', terminal.name, '- marker removed');
      }
    })
  );

  const interval = setInterval(() => {
    try {
      if (!fs.existsSync(SNOOZE_DIR)) return;
      const files = fs.readdirSync(SNOOZE_DIR);
      if (files.length === 0) return;

      for (const termName of files) {
        // Skip dotfiles / non-marker files
        if (termName.startsWith('.')) continue;

        // Check if the tmux session is still alive
        try {
          execSync('tmux has-session -t ' + JSON.stringify(termName) + ' 2>/dev/null', { timeout: 3000 });
        } catch {
          // Tmux session is gone; clean up marker
          try { fs.unlinkSync(path.join(SNOOZE_DIR, termName)); } catch (e) {}
          console.log('[claude-snooze] Tmux session gone, cleaned up:', termName);
          continue;
        }

        // Check if we already have a visible terminal for this session
        const exists = vscode.window.terminals.some(t => t.name === termName);
        if (exists) continue;

        // Open a terminal that attaches to the existing tmux session
        console.log('[claude-snooze] Opening terminal for:', termName);
        const terminal = vscode.window.createTerminal({
          name: termName,
          location: vscode.TerminalLocation.Editor,
          shellPath: '/usr/bin/tmux',
          shellArgs: ['attach-session', '-t', termName]
        });
        terminal.show();
        ourTerminals.add(termName);
      }
    } catch (e) {
      console.log('[claude-snooze] Error:', e.message);
    }
  }, 5000);

  context.subscriptions.push({ dispose: () => clearInterval(interval) });
}

function deactivate() {}

module.exports = { activate, deactivate };
