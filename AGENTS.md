# Ralph Agent Instructions

## Overview

Ralph is an autonomous AI agent loop that runs AI coding tools (Amp or Claude Code) repeatedly until all PRD items are complete. Each iteration is a fresh instance with clean context.

## Commands

```bash
# Run the flowchart dev server
cd flowchart && npm run dev

# Build the flowchart
cd flowchart && npm run build

# Run Ralph with Claude Code (from installed ralph/ directory)
./.ralph/ralph.sh --tool claude [max_iterations]

# Run Ralph with Amp
./.ralph/ralph.sh --tool amp [max_iterations]

# Run Mega-Ralph
./.ralph/mega-ralph.sh --tool claude
```

## Key Files (source repo)

- `ralph.sh` - The bash loop that spawns fresh AI instances (installs to `.ralph/ralph.sh`)
- `mega-ralph.sh` - Multi-phase orchestrator (installs to `.ralph/mega-ralph.sh`)
- `CLAUDE.md` - Instructions given to each Claude Code instance (installs to `.ralph/CLAUDE.md`)
- `prompt.md` - Instructions given to each Amp instance (installs to `.ralph/prompt.md`)
- `install.sh` - Curl-installable setup script
- `setup-repo.sh` - Local setup from source repo
- `flowchart/` - Interactive React Flow diagram explaining how Ralph works

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
- Memory persists via git history, `.state/progress.txt`, and `.state/prd.json`
- Stories should be small enough to complete in one context window
- Always update AGENTS.md with discovered patterns for future iterations
