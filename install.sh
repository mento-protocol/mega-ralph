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
VERSION="3.0.0"

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
# Migration: v2 → v3
# Detects old .state/ directory and migrates to new per-plan state structure
# ---------------------------------------------------------------------------
if [[ -d "$RALPH_DIR/.ralph" && -d "$RALPH_DIR/.state" ]]; then
  echo ""
  echo "Detected v2 structure. Migrating to v3..."
  echo ""

  # Move .state/ contents into .ralph/state/default/
  mkdir -p "$RALPH_DIR/.ralph/state/default"
  for f in prd.json progress.txt .last-branch mega-progress.json; do
    if [[ -f "$RALPH_DIR/.state/$f" ]]; then
      mv "$RALPH_DIR/.state/$f" "$RALPH_DIR/.ralph/state/default/"
      echo "  [move] .state/$f → .ralph/state/default/$f"
    fi
  done

  # Rename mega-progress.json → masterplan.json
  if [[ -f "$RALPH_DIR/.ralph/state/default/mega-progress.json" ]]; then
    mv "$RALPH_DIR/.ralph/state/default/mega-progress.json" "$RALPH_DIR/.ralph/state/default/masterplan.json"
    echo "  [rename] mega-progress.json → masterplan.json"
  fi

  # Create current symlink
  ln -sfn "state/default" "$RALPH_DIR/.ralph/current"
  echo "  [done] current → state/default"

  # Move tasks/ → plans/
  if [[ -d "$RALPH_DIR/tasks" ]]; then
    if [[ -d "$RALPH_DIR/plans" ]]; then
      # Merge into existing plans/
      mv "$RALPH_DIR/tasks/"* "$RALPH_DIR/plans/" 2>/dev/null || true
      rmdir "$RALPH_DIR/tasks" 2>/dev/null || true
    else
      mv "$RALPH_DIR/tasks" "$RALPH_DIR/plans"
    fi
    echo "  [move] tasks/ → plans/"
  fi

  # Move archive/ into .ralph/
  if [[ -d "$RALPH_DIR/archive" ]]; then
    mkdir -p "$RALPH_DIR/.ralph/archive"
    mv "$RALPH_DIR/archive/"* "$RALPH_DIR/.ralph/archive/" 2>/dev/null || true
    rmdir "$RALPH_DIR/archive" 2>/dev/null || true
    echo "  [move] archive/ → .ralph/archive/"
  fi

  # Move MASTER_PLAN.md into plans/ with new naming
  if [[ -f "$RALPH_DIR/MASTER_PLAN.md" ]]; then
    mkdir -p "$RALPH_DIR/plans"
    DATE=$(date +%Y-%m-%d)
    mv "$RALPH_DIR/MASTER_PLAN.md" "$RALPH_DIR/plans/${DATE}-M1-masterplan.md"
    echo "  [move] MASTER_PLAN.md → plans/${DATE}-M1-masterplan.md"
  fi

  # Clean up old directories
  rmdir "$RALPH_DIR/.state" 2>/dev/null || true

  # Remove old .gitignore (will be recreated with new content)
  rm -f "$RALPH_DIR/.gitignore"

  echo ""
  echo "Migration complete!"
  echo ""

# ---------------------------------------------------------------------------
# Migration: v1 (flat structure) → v3
# ---------------------------------------------------------------------------
elif [[ -f "$RALPH_DIR/ralph.sh" && ! -d "$RALPH_DIR/.ralph" ]]; then
  echo ""
  echo "Detected v1 (flat) structure. Migrating to v3..."
  echo ""

  mkdir -p "$RALPH_DIR/.ralph"
  mkdir -p "$RALPH_DIR/.ralph/state/default"

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

  # Move runtime state files to .ralph/state/default/
  for f in prd.json progress.txt .last-branch mega-progress.json; do
    if [[ -f "$RALPH_DIR/$f" ]]; then
      mv "$RALPH_DIR/$f" "$RALPH_DIR/.ralph/state/default/"
      echo "  [move] $f → .ralph/state/default/$f"
    fi
  done

  # Rename mega-progress.json → masterplan.json
  if [[ -f "$RALPH_DIR/.ralph/state/default/mega-progress.json" ]]; then
    mv "$RALPH_DIR/.ralph/state/default/mega-progress.json" "$RALPH_DIR/.ralph/state/default/masterplan.json"
    echo "  [rename] mega-progress.json → masterplan.json"
  fi

  # Create current symlink
  ln -sfn "state/default" "$RALPH_DIR/.ralph/current"

  # Move tasks/ → plans/
  if [[ -d "$RALPH_DIR/tasks" ]]; then
    mv "$RALPH_DIR/tasks" "$RALPH_DIR/plans"
    echo "  [move] tasks/ → plans/"
  fi

  # Move archive/ into .ralph/
  if [[ -d "$RALPH_DIR/archive" ]]; then
    mkdir -p "$RALPH_DIR/.ralph/archive"
    mv "$RALPH_DIR/archive/"* "$RALPH_DIR/.ralph/archive/" 2>/dev/null || true
    rmdir "$RALPH_DIR/archive" 2>/dev/null || true
    echo "  [move] archive/ → .ralph/archive/"
  fi

  # Move MASTER_PLAN.md into plans/ with new naming
  if [[ -f "$RALPH_DIR/MASTER_PLAN.md" ]]; then
    mkdir -p "$RALPH_DIR/plans"
    DATE=$(date +%Y-%m-%d)
    mv "$RALPH_DIR/MASTER_PLAN.md" "$RALPH_DIR/plans/${DATE}-M1-masterplan.md"
    echo "  [move] MASTER_PLAN.md → plans/${DATE}-M1-masterplan.md"
  fi

  # Remove old .gitignore
  rm -f "$RALPH_DIR/.gitignore"

  echo ""
  echo "Migration complete!"
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
mkdir -p "$RALPH_DIR/.ralph/state"
mkdir -p "$RALPH_DIR/.ralph/archive"
mkdir -p "$RALPH_DIR/plans"

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
fi

# ---------------------------------------------------------------------------
# Create .gitignore (always overwrite — infrastructure, not user content)
# ---------------------------------------------------------------------------
echo ""
cat > "$RALPH_DIR/.gitignore" <<'EOGITIGNORE'
# Ralph infrastructure and state (managed by installer, regenerated each run)
.ralph/

# OS files
.DS_Store

# Claude Code internal
.claude/
EOGITIGNORE
echo "  [done] .gitignore"

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
echo "    plans/                - PRD & masterplan files (committed)"
echo "    .gitignore            - Ignores .ralph/ directory"
echo ""
echo "    .ralph/               - Infrastructure (gitignored, regenerated)"
echo "      ralph.sh            - Agent loop"
if $MEGA; then
echo "      mega-ralph.sh       - Multi-phase orchestrator"
fi
echo "      state/              - Per-plan runtime state"
echo "      archive/            - Completed run archives"
echo "      skills/             - Skill definitions"
echo ""
echo "Next steps:"
echo ""
if $MEGA; then
echo "  1. Create a masterplan: use Claude with the /masterplan skill"
echo "     (saves to plans/<date>-M1-<name>.md)"
echo "  2. Run: cd $RALPH_DIR && ./.ralph/mega-ralph.sh --plan M1 --tool claude"
else
echo "  1. Create a PRD:  use Claude with the /prd skill"
echo "  2. Convert it:    use Claude with the /ralph skill"
echo "  3. Run:           cd $RALPH_DIR && ./.ralph/ralph.sh --tool claude"
echo ""
echo "  For multi-phase projects, re-run with --mega:"
echo "    curl -sL $REPO_RAW/install.sh | bash -s -- --mega"
fi
echo ""
