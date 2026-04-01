## Ops Task Guidelines

This is an operational task, not a code-change task. You will NOT create a git branch, worktree, or pull request.

### Completion
When you have completed all acceptance criteria from your plan:
1. Update `.lucy-plan.md` with checkmarks next to completed criteria
2. Create `.lucy-done.md` with:
   - Summary of what was done
   - Evidence for each acceptance criterion (screenshots, API responses, log output, etc.)
   - Any follow-up items or things to watch

### Tools available to you
- Shell commands (curl, jq, etc.)
- GitHub CLI (`gh`)
- Any APIs accessible from this environment
- Chrome DevTools MCP (if browser interaction is needed)

### What NOT to do
- Do not create pull requests (ops tasks skip the PR pipeline)
- Do not commit to main unless the task specifically requires it
- Do not modify production systems without verifying in staging/preview first
- Do not store credentials in files; use environment variables
