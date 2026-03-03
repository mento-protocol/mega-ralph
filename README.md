# Ralph

![Mega-Ralph](ralph.png)

Ralph is an autonomous AI agent loop that runs AI coding tools ([Amp](https://ampcode.com) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context. Memory persists via git history, `.state/progress.txt`, and `.state/prd.json`.

**Mega-Ralph** extends this to multi-phase projects — it reads a `MASTER_PLAN.md`, generates PRDs for each phase, and runs Ralph phase-by-phase until the entire project is done.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/).

[Read my in-depth article on how I use Ralph](https://x.com/ryancarson/status/2008548371712135632)

## Prerequisites

- One of the following AI coding tools installed and authenticated:
  - [Amp CLI](https://ampcode.com) (default)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` installed (`brew install jq` on macOS)
- A git repository for your project

## Install

Run the installer from your project root. It downloads everything you need into a `ralph/` directory.

```bash
# Single-feature workflow (ralph)
curl -sL https://raw.githubusercontent.com/mento-protocol/mega-ralph/main/install.sh | bash

# Multi-phase workflow (mega-ralph)
curl -sL https://raw.githubusercontent.com/mento-protocol/mega-ralph/main/install.sh | bash -s -- --mega
```

The installer is idempotent — infrastructure files are always updated, user content (MASTER_PLAN.md, .gitignore) is preserved. Run it again anytime to update to the latest version.

### What gets installed

```
your-project/
  ralph/
    MASTER_PLAN.md              # Your project plan (only with --mega)
    tasks/                      # PRD markdown files
    archive/                    # Completed run archives
    .gitignore

    .ralph/                     # Infrastructure (managed by installer)
      VERSION                   # Version tracking
      ralph.sh                  # Agent loop
      mega-ralph.sh             # Multi-phase orchestrator (--mega)
      CLAUDE.md                 # Agent instructions (Claude Code)
      prompt.md                 # Agent instructions (Amp)
      mega-claude-prompt.md     # Phase PRD generation template (--mega)
      mega-ralph-convert-prompt.md  # Phase PRD conversion template (--mega)
      skills/
        prd/SKILL.md            # /prd - generate PRDs
        ralph/SKILL.md          # /ralph - convert PRDs to prd.json
        masterplan/SKILL.md     # /masterplan - plan multi-phase projects

    .state/                     # Runtime state (gitignored)
      prd.json                  # Current PRD (generated per run)
      progress.txt              # Agent learnings log
      mega-progress.json        # Phase tracking (mega-ralph)
      .last-branch              # Branch change detection
```

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

Answer the clarifying questions. Output goes to `tasks/prd-[feature-name].md`.

### 2. Convert to Ralph format

```
/ralph convert tasks/prd-[feature-name].md
```

Creates `.state/prd.json` with user stories structured for autonomous execution.

### 3. Run Ralph

```bash
cd ralph

# Using Claude Code
./.ralph/ralph.sh --tool claude [max_iterations]

# Using Amp
./.ralph/ralph.sh --tool amp [max_iterations]
```

Ralph will:
1. Create a feature branch (from `branchName` in prd.json)
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

The skill does deep discovery on your codebase/domain, asks clarifying questions, then generates a `MASTER_PLAN.md` with 10-25 ordered phases.

### 2. Review and edit the plan

Open `ralph/MASTER_PLAN.md` and adjust phases, ordering, or scope. Each phase should have 3-8 user stories worth of work.

### 3. Run Mega-Ralph

```bash
cd ralph
./.ralph/mega-ralph.sh --tool claude
```

Mega-Ralph will, for each phase:
1. Generate a detailed PRD from the master plan
2. Convert it to `.state/prd.json`
3. Run Ralph to execute all stories in that phase
4. Archive the phase and move to the next

```bash
# Resume from a specific phase
./.ralph/mega-ralph.sh --tool claude --start-phase 5

# Limit iterations per phase
./.ralph/mega-ralph.sh --tool claude --max-iterations-per-phase 15
```

Progress is tracked in `.state/mega-progress.json`.

---

## Critical Concepts

### Each Iteration = Fresh Context

Each iteration spawns a **new AI instance** with clean context. The only memory between iterations is:
- Git history (commits from previous iterations)
- `.state/progress.txt` (learnings and context)
- `.state/prd.json` (which stories are done)

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
# See which stories are done
cat .state/prd.json | jq '.userStories[] | {id, title, passes}'

# See learnings from previous iterations
cat .state/progress.txt

# Check git history
git log --oneline -10

# Check mega-ralph progress
cat .state/mega-progress.json | jq '.phases[] | {phase, title, status}'

# Check installed version
cat .ralph/VERSION
```

## Flowchart

[![Ralph Flowchart](ralph-flowchart.png)](https://snarktank.github.io/ralph/)

**[View Interactive Flowchart](https://snarktank.github.io/ralph/)** - Click through to see each step with animations.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [Amp documentation](https://ampcode.com/manual)
- [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code)
