# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs AI coding tools (Amp or Claude Code) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph with Claude Code (from installed project directory)
.ralph/run.sh --tool claude [max_iterations]

# Run Ralph with Amp
.ralph/run.sh --tool amp [max_iterations]

# Run Mega-Ralph
.ralph/run.sh --plan M1 --tool claude

# Check status
.ralph/run.sh status

# Switch between plans
.ralph/run.sh switch
```

## Key Files (source repo)

- `run.sh` - Unified entry point: agent loop + multi-phase orchestrator (installs to `.ralph/run.sh`)
- `CLAUDE.md` - Instructions given to each Claude Code instance (installs to `.ralph/CLAUDE.md`)
- `prompt.md` - Instructions given to each Amp instance (installs to `.ralph/prompt.md`)
- `mega-claude-prompt.md` - Phase PRD generation template (installs to `.ralph/mega-claude-prompt.md`)
- `mega-ralph-convert-prompt.md` - Phase PRD conversion template (installs to `.ralph/mega-ralph-convert-prompt.md`)
- `mega-ralph-reflect-prompt.md` - Phase reflection template (installs to `.ralph/mega-ralph-reflect-prompt.md`)
- `install.sh` - Curl-installable setup script
- `setup-repo.sh` - Local setup from source repo
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

## Directory Structure (installed in a project)

```
your-project/
  plans/                    # PRD & masterplan files (committed)
  .ralph/                   # Infrastructure (gitignored)
    run.sh                  # Unified entry point
    CLAUDE.md               # Agent instructions (Claude Code)
    prompt.md               # Agent instructions (Amp)
    state/                  # Per-plan runtime state
      M1/                   # Masterplan 1 state
      P1/                   # Standalone PRD 1 state
    current -> state/M1     # Symlink to active state dir
    archive/                # Completed phase archives
    skills/                 # Skill definitions
```

## Flowchart

The `flowchart/` directory contains an interactive visualization built with React Flow. It's designed for presentations - click through to reveal each step with animations.

To run locally:
```bash
cd flowchart
npm install
npm run dev
```

## Patterns

- Each iteration spawns a fresh AI instance (Amp or Claude Code) with clean context
- Memory persists via git history, `.ralph/current/progress.txt`, and `.ralph/current/prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations
- User can interject between iterations via `.ralph/current/interjection.md`
