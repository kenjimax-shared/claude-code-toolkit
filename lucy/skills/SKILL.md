---
name: lucy
description: "When the user addresses Lucy directly or wants to spawn coding agents, monitor agents, or manage multi-agent tasks. Trigger phrases: 'Lucy', 'Lucy,', 'hey Lucy', 'have Lucy do', 'tell Lucy to', 'ask Lucy to', 'Lucy start', 'Lucy spawn', 'Lucy check', 'Lucy status', 'Lucy kill', 'spawn an agent', 'spawn a worker', 'kick off a task', 'start an agent on', 'run an agent', 'orchestrate', 'monitor agents', or asks to do something 'in the background' or 'in parallel'."
---

# Lucy: Multi-Agent Orchestrator

You are helping the user manage Lucy, a multi-agent coding and ops orchestrator. Lucy spawns parallel Claude Code and Codex agents in git worktrees, monitors them, runs quality gates, and does adversarial review.

When the user addresses "Lucy" directly (e.g., "Lucy, start a task on MyProject"), treat it as a command to the Lucy system and execute accordingly.

## Available Commands

All commands are in the user's PATH (`~/.claude/lucy/bin/`):

### Spawning agents
```bash
lucy-spawn --repo <name> --desc "<task description>" [options]
```
Options:
- `--type feature|bugfix|refactor|ops` (default: feature)
- `--model sonnet|opus|haiku|codex|codex-max|codex-mini|gpt54` (auto-selected if omitted)
- `--issue <number>` GitHub issue number (fetches body for context)
- `--context <file>` Context file from `~/.claude/lucy/context/` (e.g., `project.md`, `shared.md`, `client.md`)
- `--slug <text>` Custom slug for branch name
- `--max-retries <n>` Max retries on failure (default: 3)

### Monitoring
- `lucy-status` : Dashboard of all tasks
- `lucy-log <task-id>` : Parsed agent activity
- `lucy-log <task-id> --raw` : Raw stream-json
- `lucy-orchestrate [--model sonnet|opus] [--detach]` : Launch the live orchestrator

### Control
- `lucy-redirect <task-id> "<message>"` : Send course correction to running agent
- `lucy-kill <task-id> [--clean]` : Stop an agent
- `lucy-gate <task-id> [--fix]` : Run lint/test/typecheck gates
- `lucy-review <task-id>` : Trigger adversarial code review
- `lucy-verify <task-id>` : Verify ops task acceptance criteria

## How to Parse User Requests

When the user asks Lucy to do something, extract:
1. **Repo**: Which repository? Match against `~/Claude/` directories.
2. **Description**: What should the agent do?
3. **Type**: Is this a feature, bugfix, refactor, or ops task?
   - Code changes with PRs = feature/bugfix/refactor
   - Operational work (tracking setup, API config, verification) = ops
4. **Model**: Did they specify? If not, auto-selected:
   - Default: sonnet
   - Hard problems (architecture, migration, security audit, rewrites, concurrency): gpt54 (GPT-5.4 xhigh)
   - User can always override with `--model`
5. **Issue**: Did they reference a GitHub issue number?
6. **Context**: Which business context applies?
   - MyProject repos: use `--context project.md`
   - Client repos: use `--context client.md`
   - Always add `--context shared.md` knowledge to the prompt

## Task Types

### Code tasks (feature/bugfix/refactor)
Pipeline: spawn > agent plans > agent works > PR created > CI checks > quality gates > adversarial review (Codex/o3) > ready to merge

### Ops tasks
Pipeline: spawn > agent plans > agent executes > agent marks done > antagonistic verification > ready

Ops tasks:
- Don't create git worktrees (work in the repo directory directly, or no repo)
- Don't create PRs
- Complete by writing `.lucy-done.md`
- Get verified by GPT-5.4 xhigh (antagonistic verification of each acceptance criterion)

## Planning Phase

ALL tasks (code and ops) start with a planning phase. The agent writes `.lucy-plan.md` before doing any work. The plan contains:
- Assumptions about current state
- Numbered acceptance criteria that are specific and verifiable
- Each criterion is checked by the reviewer at completion

## Examples

User: "Lucy, fix the pricing API for CA3"
> `lucy-spawn --repo MyProject --type bugfix --model sonnet --context project.md --desc "Fix the pricing API for CA3 region"`

User: "have Lucy set up server-side tracking on example.com"
> `lucy-spawn --repo MyProject --type ops --model sonnet --context project.md --desc "Set up server-side GTM tracking on example.com and verify all conversion tags fire correctly"`

User: "Lucy, run 3 agents in parallel on ClientProject"
> Spawn 3 separate `lucy-spawn` commands with different task descriptions

User: "Lucy, how are things going?"
> Run `lucy-status` and interpret the output

User: "Lucy, start the orchestrator"
> Run `lucy-orchestrate` or `lucy-orchestrate --detach`

User: "tell Lucy to kill the myproject task"
> Run `lucy-kill <task-id>` for the matching MyProject task

## After Spawning

After spawning an agent, always:
1. Show the user the task ID and how to check on it
2. The orchestrator auto-starts on first spawn (opus model, tmux session `lucy-orch`). No need to start it manually.
3. Tell the user the dashboard URL for live monitoring
