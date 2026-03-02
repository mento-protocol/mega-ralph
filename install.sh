#!/bin/bash
# install.sh - Install Ralph into any project repository
#
# Quick install (basic ralph):
#   curl -sL https://raw.githubusercontent.com/snarktank/ralph/main/install.sh | bash
#
# Install with mega-ralph (multi-phase projects):
#   curl -sL https://raw.githubusercontent.com/snarktank/ralph/main/install.sh | bash -s -- --mega
#
# Run locally:
#   bash install.sh [--mega]

set -e

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_RAW="https://raw.githubusercontent.com/snarktank/ralph/main"
RALPH_DIR="ralph"
MEGA=false

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --mega)
      MEGA=true
      shift
      ;;
    -h|--help)
      echo "Usage: install.sh [--mega]"
      echo ""
      echo "Install Ralph into the current directory."
      echo ""
      echo "Options:"
      echo "  --mega    Also install mega-ralph for multi-phase projects"
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
# Helpers
# ---------------------------------------------------------------------------
download() {
  local url="$1"
  local dest="$2"
  local dir
  dir=$(dirname "$dest")
  mkdir -p "$dir"

  if command -v curl &>/dev/null; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget &>/dev/null; then
    wget -q "$url" -O "$dest"
  else
    echo "Error: Neither curl nor wget found. Install one and retry."
    exit 1
  fi
}

download_if_missing() {
  local url="$1"
  local dest="$2"
  local label="$3"

  if [[ -f "$dest" ]]; then
    echo "  [skip] $label (already exists)"
  else
    download "$url" "$dest"
    echo "  [done] $label"
  fi
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if [[ -d "$RALPH_DIR" ]]; then
  echo "Ralph is already set up in this directory ($RALPH_DIR/)."
  echo ""
  echo "To update, delete the ralph/ directory and re-run this script."
  echo "To add mega-ralph support to an existing install:"
  echo "  curl -sL $REPO_RAW/install.sh | bash -s -- --mega"
  if ! $MEGA; then
    exit 0
  fi
  echo ""
  echo "Continuing to install mega-ralph files..."
fi

if [[ ! -d ".git" ]]; then
  echo "Warning: This directory is not a git repository."
  echo "Ralph works best with git. Consider running 'git init' first."
  echo ""
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
echo ""
echo "Installing Ralph..."
echo ""

mkdir -p "$RALPH_DIR"
mkdir -p "$RALPH_DIR/tasks"
mkdir -p "$RALPH_DIR/archive"
mkdir -p "$RALPH_DIR/skills/prd"
mkdir -p "$RALPH_DIR/skills/ralph"
mkdir -p "$RALPH_DIR/skills/masterplan"

# ---------------------------------------------------------------------------
# Download core files
# ---------------------------------------------------------------------------
echo "Core files:"
download_if_missing "$REPO_RAW/ralph.sh"   "$RALPH_DIR/ralph.sh"   "ralph.sh"
download_if_missing "$REPO_RAW/CLAUDE.md"  "$RALPH_DIR/CLAUDE.md"  "CLAUDE.md"
download_if_missing "$REPO_RAW/prompt.md"  "$RALPH_DIR/prompt.md"  "prompt.md"

# ---------------------------------------------------------------------------
# Download skills
# ---------------------------------------------------------------------------
echo ""
echo "Skills:"
download_if_missing "$REPO_RAW/skills/prd/SKILL.md"        "$RALPH_DIR/skills/prd/SKILL.md"        "skills/prd/SKILL.md"
download_if_missing "$REPO_RAW/skills/ralph/SKILL.md"      "$RALPH_DIR/skills/ralph/SKILL.md"      "skills/ralph/SKILL.md"
download_if_missing "$REPO_RAW/skills/masterplan/SKILL.md" "$RALPH_DIR/skills/masterplan/SKILL.md" "skills/masterplan/SKILL.md"

# ---------------------------------------------------------------------------
# Mega-ralph files
# ---------------------------------------------------------------------------
if $MEGA; then
  echo ""
  echo "Mega-ralph (multi-phase):"
  download_if_missing "$REPO_RAW/mega-ralph.sh"                "$RALPH_DIR/mega-ralph.sh"                "mega-ralph.sh"
  download_if_missing "$REPO_RAW/mega-claude-prompt.md"        "$RALPH_DIR/mega-claude-prompt.md"        "mega-claude-prompt.md"
  download_if_missing "$REPO_RAW/mega-ralph-convert-prompt.md" "$RALPH_DIR/mega-ralph-convert-prompt.md" "mega-ralph-convert-prompt.md"

  # Create MASTER_PLAN.md template
  if [[ ! -f "$RALPH_DIR/MASTER_PLAN.md" ]]; then
    cat > "$RALPH_DIR/MASTER_PLAN.md" <<'EOTEMPLATE'
# Master Plan: [Project Name]

## Overview

[Describe the overall project. What are you building? What is the end goal?]

## Architecture & Design Decisions

[Key architectural decisions that apply across all phases.
Include technology choices, patterns, conventions, etc.]

## Phases

### Phase 1 -- Project Setup & Foundation

[Describe what this phase accomplishes. Include:
- Key deliverables
- Technology stack setup
- Foundation that later phases build on]

### Phase 2 -- [Phase Title]

[Describe what this phase accomplishes. Be specific about:
- Features to implement
- How it builds on Phase 1
- Acceptance criteria for the phase as a whole]

### Phase 3 -- [Phase Title]

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
# Create .gitignore
# ---------------------------------------------------------------------------
echo ""
if [[ ! -f "$RALPH_DIR/.gitignore" ]]; then
  cat > "$RALPH_DIR/.gitignore" <<'EOGITIGNORE'
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
  echo "  [done] .gitignore"
else
  echo "  [skip] .gitignore (already exists)"
fi

# ---------------------------------------------------------------------------
# Set permissions
# ---------------------------------------------------------------------------
chmod +x "$RALPH_DIR/ralph.sh" 2>/dev/null || true
chmod +x "$RALPH_DIR/mega-ralph.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  Ralph installed successfully!"
echo "================================================================"
echo ""
echo "  $RALPH_DIR/"
echo "    ralph.sh          - Autonomous agent loop"
echo "    CLAUDE.md         - Agent instructions"
echo "    prompt.md         - Amp agent instructions"
echo "    skills/           - PRD, Ralph, and Masterplan skills"
if $MEGA; then
echo "    mega-ralph.sh     - Multi-phase orchestrator"
echo "    MASTER_PLAN.md    - Edit this with your phase plan"
fi
echo ""
echo "Next steps:"
echo ""
if $MEGA; then
echo "  1. Edit $RALPH_DIR/MASTER_PLAN.md with your project phases"
echo "     (or use the /masterplan skill to generate one)"
echo "  2. Run: cd $RALPH_DIR && ./mega-ralph.sh --tool claude"
else
echo "  1. Create a PRD:  use Claude with the /prd skill"
echo "  2. Convert it:    use Claude with the /ralph skill"
echo "  3. Run:           cd $RALPH_DIR && ./ralph.sh --tool claude"
echo ""
echo "  For multi-phase projects, re-run with --mega:"
echo "    curl -sL $REPO_RAW/install.sh | bash -s -- --mega"
fi
echo ""
