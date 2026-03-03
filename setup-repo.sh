#!/bin/bash
# setup-repo.sh - Set up a repository for Ralph usage
#
# Run this script FROM INSIDE your target project repository to set it up
# with Ralph's autonomous agent tooling.
#
# Usage:
#   /path/to/ralph/setup-repo.sh [--mega]
#
# Options:
#   --mega    Also set up mega-ralph for multi-phase projects

set -e

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
MEGA=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --mega)
      MEGA=true
      shift
      ;;
    -h|--help)
      echo "Usage: setup-repo.sh [--mega]"
      echo ""
      echo "Run from inside your target project repository."
      echo ""
      echo "Options:"
      echo "  --mega    Also set up mega-ralph for multi-phase projects"
      echo "  -h, --help  Show this help"
      exit 0
      ;;
    *)
      echo "Error: Unknown argument '$1'. Use --help for usage."
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
# RALPH_HOME is where the ralph source files live (where this script is)
RALPH_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# TARGET_DIR is the project repo (current working directory)
TARGET_DIR="$(pwd)"
RALPH_DIR="$TARGET_DIR/ralph"

# Sanity checks
if [[ "$RALPH_HOME" == "$TARGET_DIR" ]]; then
  echo "Error: You are running this from inside the ralph repo itself."
  echo "Run this from inside your TARGET project directory:"
  echo "  cd /path/to/your/project"
  echo "  $RALPH_HOME/setup-repo.sh"
  exit 1
fi

if [[ ! -d "$TARGET_DIR/.git" ]]; then
  echo "Warning: Current directory does not appear to be a git repository."
  echo "Ralph works best with git. Consider running 'git init' first."
  echo ""
  read -r -p "Continue anyway? [y/N] " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
echo "Setting up Ralph in: $RALPH_DIR"
echo ""

mkdir -p "$RALPH_DIR/.ralph/skills/prd"
mkdir -p "$RALPH_DIR/.ralph/skills/ralph"
mkdir -p "$RALPH_DIR/.ralph/skills/masterplan"
mkdir -p "$RALPH_DIR/.state"
mkdir -p "$RALPH_DIR/tasks"
mkdir -p "$RALPH_DIR/archive"

# ---------------------------------------------------------------------------
# Copy infrastructure files (always overwrite)
# ---------------------------------------------------------------------------
echo "Infrastructure (.ralph/):"
cp -f "$RALPH_HOME/ralph.sh" "$RALPH_DIR/.ralph/ralph.sh"
chmod +x "$RALPH_DIR/.ralph/ralph.sh"
echo "  [done] ralph.sh"

cp -f "$RALPH_HOME/CLAUDE.md" "$RALPH_DIR/.ralph/CLAUDE.md"
echo "  [done] CLAUDE.md"

if [[ -f "$RALPH_HOME/prompt.md" ]]; then
  cp -f "$RALPH_HOME/prompt.md" "$RALPH_DIR/.ralph/prompt.md"
  echo "  [done] prompt.md"
fi

# ---------------------------------------------------------------------------
# Copy skills (always overwrite)
# ---------------------------------------------------------------------------
echo ""
echo "Skills (.ralph/skills/):"
if [[ -d "$RALPH_HOME/skills" ]]; then
  cp -f "$RALPH_HOME/skills/prd/SKILL.md" "$RALPH_DIR/.ralph/skills/prd/SKILL.md"
  cp -f "$RALPH_HOME/skills/ralph/SKILL.md" "$RALPH_DIR/.ralph/skills/ralph/SKILL.md"
  cp -f "$RALPH_HOME/skills/masterplan/SKILL.md" "$RALPH_DIR/.ralph/skills/masterplan/SKILL.md"
  echo "  [done] skills/prd/SKILL.md"
  echo "  [done] skills/ralph/SKILL.md"
  echo "  [done] skills/masterplan/SKILL.md"
fi

# ---------------------------------------------------------------------------
# Mega-ralph setup
# ---------------------------------------------------------------------------
if $MEGA; then
  echo ""
  echo "Mega-ralph (.ralph/):"

  cp -f "$RALPH_HOME/mega-ralph.sh" "$RALPH_DIR/.ralph/mega-ralph.sh"
  chmod +x "$RALPH_DIR/.ralph/mega-ralph.sh"
  echo "  [done] mega-ralph.sh"

  cp -f "$RALPH_HOME/mega-claude-prompt.md" "$RALPH_DIR/.ralph/mega-claude-prompt.md"
  echo "  [done] mega-claude-prompt.md"

  cp -f "$RALPH_HOME/mega-ralph-convert-prompt.md" "$RALPH_DIR/.ralph/mega-ralph-convert-prompt.md"
  echo "  [done] mega-ralph-convert-prompt.md"

  # Create MASTER_PLAN.md template (user content — only if missing)
  echo ""
  echo "User content:"
  if [[ ! -f "$RALPH_DIR/MASTER_PLAN.md" ]]; then
    cat > "$RALPH_DIR/MASTER_PLAN.md" <<'EOTEMPLATE'
# Master Plan: [Project Name]

## Overview

[Describe the overall project. What are you building? What is the end goal?]

## Architecture & Design Decisions

[Key architectural decisions that apply across all phases.
Include technology choices, patterns, conventions, etc.]

## Phases

### Phase 1: Project Setup & Foundation

[Describe what this phase accomplishes. Include:
- Key deliverables
- Technology stack setup
- Foundation that later phases build on]

### Phase 2: [Phase Title]

[Describe what this phase accomplishes. Be specific about:
- Features to implement
- How it builds on Phase 1
- Acceptance criteria for the phase as a whole]

### Phase 3: [Phase Title]

[Continue adding phases as needed. Each phase should be:
- Self-contained enough to have its own PRD
- Build on previous phases
- Completable in ~5-15 ralph iterations (5-15 user stories)]

## Dependencies & Ordering

[Note any critical dependencies between phases.
Phases are executed in order, so earlier phases must not depend on later ones.]

## Non-Goals

[What this project will NOT include, to manage scope.]
EOTEMPLATE
    echo "  [done] MASTER_PLAN.md (template)"
  else
    echo "  [skip] MASTER_PLAN.md (already exists)"
  fi
fi

# ---------------------------------------------------------------------------
# Create .gitignore for ralph/ (only if missing)
# ---------------------------------------------------------------------------
echo ""
GITIGNORE_FILE="$RALPH_DIR/.gitignore"
if [[ ! -f "$GITIGNORE_FILE" ]]; then
  cat > "$GITIGNORE_FILE" <<'EOGITIGNORE'
# Runtime state (regenerated each run)
.state/

# OS files
.DS_Store

# Claude Code internal
.claude/
EOGITIGNORE
  echo "  [done] .gitignore"
else
  echo "  [skip] .gitignore (already exists)"
fi

# ---------------------------------------------------------------------------
# Write VERSION
# ---------------------------------------------------------------------------
echo "2.1.0" > "$RALPH_DIR/.ralph/VERSION"

# ---------------------------------------------------------------------------
# Print instructions
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  Ralph setup complete!"
echo "================================================================"
echo ""
echo "Directory structure:"
echo "  $RALPH_DIR/"
echo "    .ralph/               - Infrastructure (scripts, templates, skills)"
echo "    .state/               - Runtime state (gitignored)"
echo "    tasks/                - PRD files"
echo "    archive/              - Completed run archives"
if $MEGA; then
echo "    MASTER_PLAN.md        - Edit this with your phase plan"
fi
echo ""
echo "Next steps:"
echo ""
if $MEGA; then
echo "  1. Edit ralph/MASTER_PLAN.md with your project phases"
echo "  2. Run: cd ralph && ./.ralph/mega-ralph.sh --tool claude"
else
echo "  1. Create a PRD: use Claude with the /prd skill"
echo "  2. Convert to prd.json: use Claude with the /ralph skill"
echo "  3. Run: cd ralph && ./.ralph/ralph.sh --tool claude"
fi
echo ""
echo "Tip: Add ralph/ to your repo so teammates can use the same setup."
echo ""
