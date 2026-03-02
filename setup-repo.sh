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
# Create ralph/ directory
# ---------------------------------------------------------------------------
echo "Setting up Ralph in: $RALPH_DIR"
echo ""

mkdir -p "$RALPH_DIR"
mkdir -p "$RALPH_DIR/tasks"
mkdir -p "$RALPH_DIR/archive"

# ---------------------------------------------------------------------------
# Copy ralph.sh
# ---------------------------------------------------------------------------
if [[ -f "$RALPH_DIR/ralph.sh" ]]; then
  echo "  ralph.sh already exists, skipping (use manual copy to update)"
else
  cp "$RALPH_HOME/ralph.sh" "$RALPH_DIR/ralph.sh"
  chmod +x "$RALPH_DIR/ralph.sh"
  echo "  Copied ralph.sh"
fi

# ---------------------------------------------------------------------------
# Copy CLAUDE.md template
# ---------------------------------------------------------------------------
if [[ -f "$RALPH_DIR/CLAUDE.md" ]]; then
  echo "  CLAUDE.md already exists, skipping"
else
  cp "$RALPH_HOME/CLAUDE.md" "$RALPH_DIR/CLAUDE.md"
  echo "  Copied CLAUDE.md"
fi

# ---------------------------------------------------------------------------
# Copy prompt.md template (for amp tool)
# ---------------------------------------------------------------------------
if [[ -f "$RALPH_DIR/prompt.md" ]]; then
  echo "  prompt.md already exists, skipping"
else
  if [[ -f "$RALPH_HOME/prompt.md" ]]; then
    cp "$RALPH_HOME/prompt.md" "$RALPH_DIR/prompt.md"
    echo "  Copied prompt.md"
  fi
fi

# ---------------------------------------------------------------------------
# Copy skills directory
# ---------------------------------------------------------------------------
if [[ -d "$RALPH_HOME/skills" ]]; then
  if [[ -d "$RALPH_DIR/skills" ]]; then
    echo "  skills/ already exists, skipping"
  else
    cp -r "$RALPH_HOME/skills" "$RALPH_DIR/skills"
    echo "  Copied skills/"
  fi
fi

# ---------------------------------------------------------------------------
# Mega-ralph setup
# ---------------------------------------------------------------------------
if $MEGA; then
  echo ""
  echo "Setting up mega-ralph (multi-phase) support..."

  # Copy mega-ralph.sh
  if [[ -f "$RALPH_DIR/mega-ralph.sh" ]]; then
    echo "  mega-ralph.sh already exists, skipping"
  else
    cp "$RALPH_HOME/mega-ralph.sh" "$RALPH_DIR/mega-ralph.sh"
    chmod +x "$RALPH_DIR/mega-ralph.sh"
    echo "  Copied mega-ralph.sh"
  fi

  # Copy prompt templates
  if [[ -f "$RALPH_DIR/mega-claude-prompt.md" ]]; then
    echo "  mega-claude-prompt.md already exists, skipping"
  else
    cp "$RALPH_HOME/mega-claude-prompt.md" "$RALPH_DIR/mega-claude-prompt.md"
    echo "  Copied mega-claude-prompt.md"
  fi

  if [[ -f "$RALPH_DIR/mega-ralph-convert-prompt.md" ]]; then
    echo "  mega-ralph-convert-prompt.md already exists, skipping"
  else
    cp "$RALPH_HOME/mega-ralph-convert-prompt.md" "$RALPH_DIR/mega-ralph-convert-prompt.md"
    echo "  Copied mega-ralph-convert-prompt.md"
  fi

  # Create MASTER_PLAN.md template
  if [[ -f "$RALPH_DIR/MASTER_PLAN.md" ]]; then
    echo "  MASTER_PLAN.md already exists, skipping"
  else
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
    echo "  Created MASTER_PLAN.md template"
  fi
fi

# ---------------------------------------------------------------------------
# Create .gitignore for ralph/
# ---------------------------------------------------------------------------
GITIGNORE_FILE="$RALPH_DIR/.gitignore"
if [[ -f "$GITIGNORE_FILE" ]]; then
  echo "  .gitignore already exists, skipping"
else
  cat > "$GITIGNORE_FILE" <<'EOGITIGNORE'
# Ralph working files (generated during runs)
prd.json
progress.txt
.last-branch

# Mega-ralph working files
mega-progress.json

# Archive is optional to commit
# archive/

# OS files
.DS_Store

# Claude
.claude/
EOGITIGNORE
  echo "  Created .gitignore"
fi

# ---------------------------------------------------------------------------
# Make scripts executable
# ---------------------------------------------------------------------------
chmod +x "$RALPH_DIR/ralph.sh" 2>/dev/null || true
chmod +x "$RALPH_DIR/mega-ralph.sh" 2>/dev/null || true

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
echo "    ralph.sh          - Main agent loop"
echo "    CLAUDE.md         - Agent prompt template"
if [[ -f "$RALPH_DIR/prompt.md" ]]; then
echo "    prompt.md         - Amp agent prompt template"
fi
echo "    tasks/            - PRD files go here"
echo "    archive/          - Completed runs archived here"
if $MEGA; then
echo "    mega-ralph.sh     - Multi-phase orchestrator"
echo "    mega-claude-prompt.md      - PRD generation template"
echo "    mega-ralph-convert-prompt.md  - PRD conversion template"
echo "    MASTER_PLAN.md    - Edit this with your phase plan"
fi
echo ""
echo "Next steps:"
echo ""
if $MEGA; then
echo "  1. Edit ralph/MASTER_PLAN.md with your project phases"
echo "  2. Run: cd ralph && ./mega-ralph.sh --tool claude"
else
echo "  1. Create a PRD: use Claude with the 'prd' skill, or write tasks/prd-feature.md"
echo "  2. Convert to prd.json: use Claude with the 'ralph' skill"
echo "  3. Run: cd ralph && ./ralph.sh --tool claude"
fi
echo ""
echo "Tip: Add ralph/ to your repo so teammates can use the same setup."
echo ""
