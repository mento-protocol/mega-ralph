# Ralph

![Mega-Ralph](ralph.png)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Amp](https://ampcode.com), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), or [Codex CLI](https://github.com/openai/codex)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `.ralph/current/progress.txt`, and `.ralph/current/prd.json`.

**Mega-Ralph** extends this to multi-phase projects — it reads a masterplan from `plans/`, generates PRDs for each phase, and runs Ralph phase-by-phase until the entire project is done.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Amp CLI](https://ampcode.com)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
  - [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`)
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project

## Install

Run the installer from your project root. It creates `plans/` and `.ralph/` at the top level.

```bash
curl -sL https://raw.githubusercontent.com/mento-protocol/mega-ralph/main/install.sh | bash
```

The installer is idempotent — infrastructure files are always updated, user content (plans/) is preserved. Run it again anytime to update to the latest version.

### What gets installed

```
your-project/
  plans/                      # PRD & masterplan files (committed)
    2026-03-05-M1-my-project.md
    2026-03-05-M1-P01-project-setup.md
    2026-03-10-P1-add-login-button.md

  .ralph/                     # Infrastructure (gitignored)
    run.sh                    # Unified entry point
    config.sh                 # Optional config defaults (see below)
    VERSION                   # Version tracking
    CLAUDE.md                 # Agent instructions (Claude Code)
    prompt.md                 # Agent instructions (Amp)
    mega-claude-prompt.md     # Phase PRD generation template
    mega-ralph-convert-prompt.md  # Phase PRD conversion template
    mega-ralph-reflect-prompt.md  # Phase reflection template
    review-prompt.md          # Per-story review template
    review-fixes-prompt.md    # Per-story fix applier template
    phase-review-prompt.md    # Full-phase review template
    skills/
      prd/SKILL.md            # /prd - generate PRDs
      ralph/SKILL.md          # /ralph - convert PRDs to prd.json
      masterplan/SKILL.md     # /masterplan - plan multi-phase projects
    state/                    # Per-plan runtime state
      M1/                     # Masterplan 1 state
        masterplan.json       # Phase tracking
        prd.json              # Current phase PRD
        progress.txt          # Agent learnings log
        .last-branch          # Branch change detection
        interjection.md       # User notes for next iteration
        reviews/              # Review documents (when --with-review)
        .branch-config        # Stored base branch (standalone mode)
      P1/                     # Standalone PRD 1 state
        prd.json
        progress.txt
        .branch-config
    current -> state/M1       # Symlink to active state dir
    archive/                  # Completed phase archives
```

### Naming conventions

| Type | Pattern | Example |
|------|---------|---------|
| Masterplan | `<date>-M<idx>-<name>.md` | `2026-03-05-M1-my-project.md` |
| Phase PRD | `<date>-M<idx>-P<padded>-<name>.md` | `2026-03-05-M1-P03-api-layer.md` |
| Standalone PRD | `<date>-P<idx>-<name>.md` | `2026-03-10-P1-add-login.md` |

### Alternative setup methods

<details>
<summary>Install skills globally (Amp / Claude Code)</summary>

```bash
# Amp
cp -r skills/prd ~/.config/amp/skills/
cp -r skills/ralph ~/.config/amp/skills/

# Claude Code
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

</details>

<details>
<summary>Claude Code Marketplace</summary>

```bash
/plugin marketplace add mento-protocol/mega-ralph
/plugin install ralph-skills@ralph-marketplace
```

</details>

<details>
<summary>Configure Amp auto-handoff (recommended)</summary>

Add to `~/.config/amp/settings.json`:

```json
{
  "amp.experimental.autoHandoff": { "context": 90 }
}
```

This enables automatic handoff when context fills up, allowing Ralph to handle large stories that exceed a single context window.

</details>

---

## Workflow: Single Feature (Ralph)

Use this when the work fits in **one PRD** (3-8 user stories).

### 1. Create a PRD

```
/prd [your feature description]
```

Answer the clarifying questions. Output goes to `plans/prd-[feature-name].md`.

### 2. Convert to Ralph format

```
/ralph convert plans/prd-[feature-name].md
```

Creates `.ralph/current/prd.json` with user stories structured for autonomous execution.

### 3. Run Ralph

```bash
# Using Claude Code (default)
.ralph/run.sh --tool claude [max_iterations]

# Using a specific model
.ralph/run.sh --tool claude --model sonnet [max_iterations]
.ralph/run.sh --tool claude --model opus [max_iterations]

# Using Amp
.ralph/run.sh --tool amp [max_iterations]

# Using Codex
.ralph/run.sh --tool codex [max_iterations]
.ralph/run.sh --tool codex --model codex-1 [max_iterations]
```

Ralph will:
1. Set up the feature branch (from `branchName` in prd.json, based on chosen base branch)
2. Pick the highest priority story where `passes: false`
3. Implement it, run quality checks, commit
4. Mark story as `passes: true`
5. Repeat until all stories pass or max iterations reached

---

## Workflow: Multi-Phase Project (Mega-Ralph)

Use this for projects **too big for a single PRD** — rewrites, ports, greenfield apps, major overhauls.

### 1. Generate a master plan

```
/masterplan [your project description]
```

The skill does deep discovery on your codebase/domain, asks clarifying questions, then generates a masterplan in `plans/` (e.g., `plans/2026-03-05-M1-my-project.md`).

### 2. Review and edit the plan

Open the masterplan in `plans/` and adjust phases, ordering, or scope. Each phase should have 3-8 user stories worth of work.

### 3. Run Mega-Ralph

```bash
.ralph/run.sh --plan M1 --tool claude
.ralph/run.sh --plan M1 --tool claude --model sonnet
.ralph/run.sh --plan M1 --tool codex
```

Mega-Ralph will, for each phase:
1. Generate a detailed PRD from the master plan
2. Convert it to `.ralph/current/prd.json`
3. Run Ralph to execute all stories in that phase
4. Archive the phase and move to the next

```bash
# Resume from a specific phase
.ralph/run.sh --plan M1 --start-phase 5

# Limit iterations per phase
.ralph/run.sh --plan M1 --tool claude --max-iterations-per-phase 15
```

Progress is tracked in `.ralph/state/M1/masterplan.json`.

### 4. Switch between plans

```bash
.ralph/run.sh switch
```

Lists all plans in `.ralph/state/`, shows progress, and lets you switch the `current` symlink interactively.

---

## Interjections

While Ralph is running, you can influence the next iteration by writing to the interjection file:

```bash
echo "Focus on error handling, not new features" > .ralph/current/interjection.md
```

Before each iteration, Ralph checks this file. If non-empty, its contents are prepended to the agent prompt and the file is cleared. This lets you steer the agent without stopping the loop.

---

## Branching Strategy

Ralph manages git branches automatically. You choose a **base branch** at startup and Ralph creates feature branches from it.

### Base Branch Selection

```bash
# Interactive prompt (default)
.ralph/run.sh --tool claude

# Skip prompt, use specific base
.ralph/run.sh --base main --tool claude
.ralph/run.sh --base develop --tool claude
```

When run interactively, Ralph prompts you to choose a base branch. On resume, the selection is remembered. Non-interactive mode (piped stdin) defaults to `main`.

### Branch Hierarchy

**Standalone Ralph:**
```
main (or chosen base)
 └─ feat/<feature-slug>       ← feature branch from prd.json branchName
```

**Mega-Ralph:**
```
main (or chosen base)
 └─ feat/M1-my-project        ← masterplan feature branch
     ├─ feat/M1-P01-setup     ← phase 1 branch (merged back after phase)
     ├─ feat/M1-P02-core      ← phase 2 branch
     └─ feat/M1-P03-api       ← phase 3 branch
```

After each phase completes, the phase branch is merged back into the masterplan feature branch. You merge the feature branch to your base branch manually (e.g., via PR).

---

## Code Review

Opt-in code review adds a quality gate after each story commit and after each completed phase.

```bash
# Enable review
.ralph/run.sh --with-review --tool claude

# Use a different model for review (e.g., opus reviews sonnet's code)
.ralph/run.sh --with-review --review-model opus --tool claude --model sonnet

# Use a different tool entirely for review
.ralph/run.sh --with-review --review-tool claude --tool amp
```

### Per-Story Review

After each story is marked `passes: true`, Ralph:
1. Runs a **review turn** — reads `git diff HEAD~1`, writes a structured review to `.ralph/current/reviews/review-<story-id>.md`
2. If the verdict is **NEEDS-FIXES**, runs a **fixes turn** — reads the review, applies only blocking fixes, commits as `fix: <story-id> review fixes`

Reviews only flag real issues: correctness bugs, security vulnerabilities, performance problems. Style nits are skipped.

### Per-Phase Review (Mega-Ralph)

After all stories in a phase complete, Ralph:
1. Runs a **phase review** — reads `git diff <parent-branch>...<phase-branch>`, writes `.ralph/current/reviews/review-phase-<N>.md`
2. If **NEEDS-FIXES**, applies blocking fixes
3. Merges the phase branch back to the masterplan feature branch

Review documents are archived with each phase for the human record.

---

## Configuration File

Create `.ralph/config.sh` to set defaults that apply to every run. CLI arguments override config values.

```bash
# .ralph/config.sh
export RALPH_TOOL=claude
export RALPH_MODEL=sonnet
export RALPH_BASE=main
export RALPH_WITH_REVIEW=true
export RALPH_REVIEW_TOOL=claude
export RALPH_REVIEW_MODEL=opus
export RALPH_MAX_ITERATIONS=15
export RALPH_MAX_ITERATIONS_PER_PHASE=25
```

This file is sourced before argument parsing, so any `--flag` on the command line takes precedence.

---

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `.ralph/current/progress.txt` (learnings and context)
- `.ralph/current/prd.json` (which stories are done)

### Small Tasks

Each PRD item should be small enough to complete in one context window. If a task is too big, the LLM runs out of context before finishing and produces poor code.

Right-sized stories:
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

Too big (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

### Feedback Loops

Ralph only works if there are feedback loops:
- Typecheck catches type errors
- Tests verify behavior
- CI must stay green (broken code compounds across iterations)

### Error Recovery

Ralph includes exponential backoff for transient errors (API quota limits, network issues). When an iteration fails with a non-zero exit code, it waits 5s, then 10s, 20s, etc. up to 5 minutes before retrying. The backoff resets after a successful iteration.

### AGENTS.md / CLAUDE.md Updates

After each iteration, Ralph updates relevant AGENTS.md / CLAUDE.md files with learnings. Future iterations (and human developers) benefit from discovered patterns, gotchas, and conventions.

### Stop Condition

When all stories have `passes: true`, Ralph outputs `<promise>COMPLETE</promise>` and the loop exits.

## Debugging

```bash
# Check current status
.ralph/run.sh status

# Switch between plans
.ralph/run.sh switch

# See which stories are done
cat .ralph/current/prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat .ralph/current/progress.txt

# Check git history
git log --oneline -10

# Check mega-ralph progress
cat .ralph/state/M1/masterplan.json | jq '.phases[] | {phase, title, status}'

# Check installed version
cat .ralph/VERSION

# Interject before next iteration
echo "Fix the failing test before proceeding" > .ralph/current/interjection.md
```

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
