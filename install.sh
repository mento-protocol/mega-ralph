#!/bin/bash
# install.sh - Install or update Ralph in any project repository
#
# Quick install (basic ralph):
#   curl -sL https://raw.githubusercontent.com/mento-protocol/mega-ralph/main/install.sh | bash
#
# Install with mega-ralph (multi-phase projects):
#   curl -sL https://raw.githubusercontent.com/mento-protocol/mega-ralph/main/install.sh | bash -s -- --mega
#
# Run locally:
#   bash install.sh [--mega]

set -e

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_RAW="https://raw.githubusercontent.com/mento-protocol/mega-ralph/main"
RALPH_DIR="ralph"
MEGA=false
VERSION="2.1.0"

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
      echo "Install or update Ralph in the current directory."
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

download_always() {
  local url="$1"
  local dest="$2"
  local label="$3"

  download "$url" "$dest"
  echo "  [done] $label"
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
if [[ ! -d ".git" ]]; then
  echo "Warning: This directory is not a git repository."
  echo "Ralph works best with git. Consider running 'git init' first."
  echo ""
fi

# ---------------------------------------------------------------------------
# Migration: detect old flat structure and move files
# ---------------------------------------------------------------------------
if [[ -f "$RALPH_DIR/ralph.sh" && ! -d "$RALPH_DIR/.ralph" ]]; then
  echo ""
  echo "Detected old ralph directory structure. Migrating to v2..."
  echo ""

  mkdir -p "$RALPH_DIR/.ralph"
  mkdir -p "$RALPH_DIR/.state"

  # Move infrastructure files to .ralph/
  for f in ralph.sh CLAUDE.md prompt.md; do
    if [[ -f "$RALPH_DIR/$f" ]]; then
      mv "$RALPH_DIR/$f" "$RALPH_DIR/.ralph/$f"
      echo "  [move] $f → .ralph/$f"
    fi
  done

  # Move mega-ralph files to .ralph/
  for f in mega-ralph.sh mega-claude-prompt.md mega-ralph-convert-prompt.md mega-ralph-reflect-prompt.md; do
    if [[ -f "$RALPH_DIR/$f" ]]; then
      mv "$RALPH_DIR/$f" "$RALPH_DIR/.ralph/$f"
      echo "  [move] $f → .ralph/$f"
    fi
  done

  # Move skills to .ralph/skills/
  if [[ -d "$RALPH_DIR/skills" ]]; then
    mv "$RALPH_DIR/skills" "$RALPH_DIR/.ralph/skills"
    echo "  [move] skills/ → .ralph/skills/"
  fi

  # Move runtime state files to .state/
  for f in prd.json progress.txt .last-branch mega-progress.json; do
    if [[ -f "$RALPH_DIR/$f" ]]; then
      mv "$RALPH_DIR/$f" "$RALPH_DIR/.state/$f"
      echo "  [move] $f → .state/$f"
    fi
  done

  # Update .gitignore for new structure
  if [[ -f "$RALPH_DIR/.gitignore" ]]; then
    rm "$RALPH_DIR/.gitignore"
    echo "  [remove] old .gitignore (will recreate)"
  fi

  echo ""
  echo "Migration complete! Files moved to new structure."
  echo ""
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
echo ""
echo "Installing Ralph v${VERSION}..."
echo ""

mkdir -p "$RALPH_DIR/.ralph"
mkdir -p "$RALPH_DIR/.ralph/skills/prd"
mkdir -p "$RALPH_DIR/.ralph/skills/ralph"
mkdir -p "$RALPH_DIR/.ralph/skills/masterplan"
mkdir -p "$RALPH_DIR/.state"
mkdir -p "$RALPH_DIR/tasks"
mkdir -p "$RALPH_DIR/archive"

# ---------------------------------------------------------------------------
# Download infrastructure files (always overwrite)
# ---------------------------------------------------------------------------
echo "Infrastructure (.ralph/):"
download_always "$REPO_RAW/ralph.sh"   "$RALPH_DIR/.ralph/ralph.sh"   "ralph.sh"
download_always "$REPO_RAW/CLAUDE.md"  "$RALPH_DIR/.ralph/CLAUDE.md"  "CLAUDE.md"
download_always "$REPO_RAW/prompt.md"  "$RALPH_DIR/.ralph/prompt.md"  "prompt.md"

# ---------------------------------------------------------------------------
# Download skills (always overwrite)
# ---------------------------------------------------------------------------
echo ""
echo "Skills (.ralph/skills/):"
download_always "$REPO_RAW/skills/prd/SKILL.md"        "$RALPH_DIR/.ralph/skills/prd/SKILL.md"        "skills/prd/SKILL.md"
download_always "$REPO_RAW/skills/ralph/SKILL.md"      "$RALPH_DIR/.ralph/skills/ralph/SKILL.md"      "skills/ralph/SKILL.md"
download_always "$REPO_RAW/skills/masterplan/SKILL.md" "$RALPH_DIR/.ralph/skills/masterplan/SKILL.md" "skills/masterplan/SKILL.md"

# ---------------------------------------------------------------------------
# Mega-ralph files (always overwrite infrastructure)
# ---------------------------------------------------------------------------
if $MEGA; then
  echo ""
  echo "Mega-ralph (.ralph/):"
  download_always "$REPO_RAW/mega-ralph.sh"                  "$RALPH_DIR/.ralph/mega-ralph.sh"                  "mega-ralph.sh"
  download_always "$REPO_RAW/mega-claude-prompt.md"          "$RALPH_DIR/.ralph/mega-claude-prompt.md"          "mega-claude-prompt.md"
  download_always "$REPO_RAW/mega-ralph-convert-prompt.md"   "$RALPH_DIR/.ralph/mega-ralph-convert-prompt.md"   "mega-ralph-convert-prompt.md"
  download_always "$REPO_RAW/mega-ralph-reflect-prompt.md"   "$RALPH_DIR/.ralph/mega-ralph-reflect-prompt.md"   "mega-ralph-reflect-prompt.md"

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
# Create .gitignore (only if missing — user content)
# ---------------------------------------------------------------------------
echo ""
if [[ ! -f "$RALPH_DIR/.gitignore" ]]; then
  cat > "$RALPH_DIR/.gitignore" <<'EOGITIGNORE'
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
echo "$VERSION" > "$RALPH_DIR/.ralph/VERSION"

# ---------------------------------------------------------------------------
# Set permissions
# ---------------------------------------------------------------------------
chmod +x "$RALPH_DIR/.ralph/ralph.sh" 2>/dev/null || true
chmod +x "$RALPH_DIR/.ralph/mega-ralph.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  Ralph v${VERSION} installed successfully!"
echo "================================================================"
echo ""
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
echo "  1. Edit $RALPH_DIR/MASTER_PLAN.md with your project phases"
echo "     (or use the /masterplan skill to generate one)"
echo "  2. Run: cd $RALPH_DIR && ./.ralph/mega-ralph.sh --tool claude"
else
echo "  1. Create a PRD:  use Claude with the /prd skill"
echo "  2. Convert it:    use Claude with the /ralph skill"
echo "  3. Run:           cd $RALPH_DIR && ./.ralph/ralph.sh --tool claude"
echo ""
echo "  For multi-phase projects, re-run with --mega:"
echo "    curl -sL $REPO_RAW/install.sh | bash -s -- --mega"
fi
echo ""
