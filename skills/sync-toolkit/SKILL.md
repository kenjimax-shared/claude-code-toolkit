---
name: sync-toolkit
description: "Sync live ~/.claude/ config to the claude-code-toolkit GitHub repo. Use when the user says 'update the Claude repo,' 'sync toolkit,' 'push config changes,' or similar. Runs the toolkit-sync script which copies infrastructure files, sanitizes PII/credentials/company names, commits, and pushes."
metadata:
  version: 1.0.0
---

# Sync Toolkit

Run the toolkit-sync script to push live Claude Code configuration changes to the public repo.

## Steps

1. Run the sync script:
```bash
bash "$HOME/.claude/lucy/bin/toolkit-sync"
```

2. Report the result to the user: how many files were synced, or if nothing changed.

3. If the script fails, show the error output so the user can diagnose.
