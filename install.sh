#!/bin/bash
# install.sh - Install or update Ralph in any project repository
#
# Install:
#   curl -sL https://raw.githubusercontent.com/mento-protocol/mega-ralph/main/install.sh | bash
#
# Run locally:
#   bash install.sh

set -e

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
REPO_RAW="https://raw.githubusercontent.com/mento-protocol/mega-ralph/main"
VERSION="4.0.0"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      echo "Usage: install.sh"
      echo ""
      echo "Install or update Ralph in the current directory."
      echo "Installs plans/ and .ralph/ at the project root."
      exit 0
      ;;
    --mega)
      # Accepted for backwards compat but ignored (always installs everything)
      shift
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

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if [[ ! -d ".git" ]]; then
  echo "Warning: This directory is not a git repository."
  echo "Ralph works best with git. Consider running 'git init' first."
  echo ""
fi

# ---------------------------------------------------------------------------
# Migration: v3 → v4
# ralph/ wrapper exists with .ralph/ inside — move to top level
# ---------------------------------------------------------------------------
if [[ -d "ralph/.ralph" ]]; then
  echo ""
  echo "Detected v3 structure. Migrating to v4..."
  echo ""

  # Move plans/ to top level
  if [[ -d "ralph/plans" ]]; then
    if [[ -d "plans" ]]; then
      # Merge into existing plans/
      mv ralph/plans/* plans/ 2>/dev/null || true
      rmdir ralph/plans 2>/dev/null || true
    else
      mv ralph/plans plans
    fi
    echo "  [move] ralph/plans/ → plans/"
  fi

  # Move .ralph/ to top level
  if [[ -d ".ralph" ]]; then
    # Merge: copy contents from ralph/.ralph/ into existing .ralph/
    cp -rn ralph/.ralph/* .ralph/ 2>/dev/null || true
    rm -rf ralph/.ralph
  else
    mv ralph/.ralph .ralph
  fi
  echo "  [move] ralph/.ralph/ → .ralph/"

  # Clean up ralph/ wrapper
  rm -f ralph/.gitignore
  rmdir ralph 2>/dev/null || true

  echo ""
  echo "v3 → v4 migration complete!"
  echo ""

# ---------------------------------------------------------------------------
# Migration: v2 → v4
# ralph/ wrapper with .state/ inside (no .ralph/)
# ---------------------------------------------------------------------------
elif [[ -d "ralph/.state" ]]; then
  echo ""
  echo "Detected v2 structure. Migrating to v4..."
  echo ""

  # First do v2 → v3 state consolidation
  mkdir -p "ralph/.ralph/state/default"
  for f in prd.json progress.txt .last-branch mega-progress.json; do
    if [[ -f "ralph/.state/$f" ]]; then
      mv "ralph/.state/$f" "ralph/.ralph/state/default/"
      echo "  [move] .state/$f → .ralph/state/default/$f"
    fi
  done

  # Rename mega-progress.json → masterplan.json
  if [[ -f "ralph/.ralph/state/default/mega-progress.json" ]]; then
    mv "ralph/.ralph/state/default/mega-progress.json" "ralph/.ralph/state/default/masterplan.json"
    echo "  [rename] mega-progress.json → masterplan.json"
  fi

  # Create current symlink
  ln -sfn "state/default" "ralph/.ralph/current"

  # Move tasks/ → plans/
  if [[ -d "ralph/tasks" ]]; then
    mv "ralph/tasks" "ralph/plans" 2>/dev/null || true
    echo "  [move] tasks/ → plans/"
  fi

  # Move archive/ into .ralph/
  if [[ -d "ralph/archive" ]]; then
    mkdir -p "ralph/.ralph/archive"
    mv ralph/archive/* "ralph/.ralph/archive/" 2>/dev/null || true
    rmdir "ralph/archive" 2>/dev/null || true
    echo "  [move] archive/ → .ralph/archive/"
  fi

  # Move MASTER_PLAN.md into plans/
  if [[ -f "ralph/MASTER_PLAN.md" ]]; then
    mkdir -p "ralph/plans"
    DATE=$(date +%Y-%m-%d)
    mv "ralph/MASTER_PLAN.md" "ralph/plans/${DATE}-M1-masterplan.md"
    echo "  [move] MASTER_PLAN.md → plans/${DATE}-M1-masterplan.md"
  fi

  rmdir "ralph/.state" 2>/dev/null || true
  rm -f "ralph/.gitignore"

  # Now do v3 → v4 (move to top level)
  if [[ -d "ralph/plans" ]]; then
    if [[ -d "plans" ]]; then
      mv ralph/plans/* plans/ 2>/dev/null || true
      rmdir ralph/plans 2>/dev/null || true
    else
      mv ralph/plans plans
    fi
    echo "  [move] ralph/plans/ → plans/"
  fi

  mv ralph/.ralph .ralph 2>/dev/null || true
  echo "  [move] ralph/.ralph/ → .ralph/"

  rm -f ralph/.gitignore
  rmdir ralph 2>/dev/null || true

  echo ""
  echo "v2 → v4 migration complete!"
  echo ""

# ---------------------------------------------------------------------------
# Migration: v1 → v4
# ralph/ wrapper with ralph.sh at top (flat structure, no .ralph/)
# ---------------------------------------------------------------------------
elif [[ -f "ralph/ralph.sh" && ! -d "ralph/.ralph" ]]; then
  echo ""
  echo "Detected v1 (flat) structure. Migrating to v4..."
  echo ""

  # First do v1 → v3 consolidation
  mkdir -p "ralph/.ralph"
  mkdir -p "ralph/.ralph/state/default"

  for f in ralph.sh CLAUDE.md prompt.md mega-ralph.sh mega-claude-prompt.md mega-ralph-convert-prompt.md mega-ralph-reflect-prompt.md; do
    if [[ -f "ralph/$f" ]]; then
      mv "ralph/$f" "ralph/.ralph/$f"
      echo "  [move] $f → .ralph/$f"
    fi
  done

  if [[ -d "ralph/skills" ]]; then
    mv "ralph/skills" "ralph/.ralph/skills"
    echo "  [move] skills/ → .ralph/skills/"
  fi

  for f in prd.json progress.txt .last-branch mega-progress.json; do
    if [[ -f "ralph/$f" ]]; then
      mv "ralph/$f" "ralph/.ralph/state/default/"
      echo "  [move] $f → .ralph/state/default/$f"
    fi
  done

  if [[ -f "ralph/.ralph/state/default/mega-progress.json" ]]; then
    mv "ralph/.ralph/state/default/mega-progress.json" "ralph/.ralph/state/default/masterplan.json"
    echo "  [rename] mega-progress.json → masterplan.json"
  fi

  ln -sfn "state/default" "ralph/.ralph/current"

  if [[ -d "ralph/tasks" ]]; then
    mv "ralph/tasks" "ralph/plans"
    echo "  [move] tasks/ → plans/"
  fi

  if [[ -d "ralph/archive" ]]; then
    mkdir -p "ralph/.ralph/archive"
    mv ralph/archive/* "ralph/.ralph/archive/" 2>/dev/null || true
    rmdir "ralph/archive" 2>/dev/null || true
    echo "  [move] archive/ → .ralph/archive/"
  fi

  if [[ -f "ralph/MASTER_PLAN.md" ]]; then
    mkdir -p "ralph/plans"
    DATE=$(date +%Y-%m-%d)
    mv "ralph/MASTER_PLAN.md" "ralph/plans/${DATE}-M1-masterplan.md"
    echo "  [move] MASTER_PLAN.md → plans/${DATE}-M1-masterplan.md"
  fi

  rm -f "ralph/.gitignore"

  # Now do v3 → v4
  if [[ -d "ralph/plans" ]]; then
    if [[ -d "plans" ]]; then
      mv ralph/plans/* plans/ 2>/dev/null || true
      rmdir ralph/plans 2>/dev/null || true
    else
      mv ralph/plans plans
    fi
    echo "  [move] ralph/plans/ → plans/"
  fi

  mv ralph/.ralph .ralph 2>/dev/null || true
  echo "  [move] ralph/.ralph/ → .ralph/"

  rm -f ralph/.gitignore
  rmdir ralph 2>/dev/null || true

  echo ""
  echo "v1 → v4 migration complete!"
  echo ""
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
echo ""
echo "Installing Ralph v${VERSION}..."
echo ""

mkdir -p ".ralph"
mkdir -p ".ralph/skills/prd"
mkdir -p ".ralph/skills/ralph"
mkdir -p ".ralph/skills/masterplan"
mkdir -p ".ralph/state"
mkdir -p ".ralph/archive"
mkdir -p "plans"

# ---------------------------------------------------------------------------
# Download infrastructure files (always overwrite)
# ---------------------------------------------------------------------------
echo "Infrastructure (.ralph/):"
download_always "$REPO_RAW/run.sh"     ".ralph/run.sh"     "run.sh"
download_always "$REPO_RAW/CLAUDE.md"  ".ralph/CLAUDE.md"  "CLAUDE.md"
download_always "$REPO_RAW/prompt.md"  ".ralph/prompt.md"  "prompt.md"

echo ""
echo "Mega-ralph templates (.ralph/):"
download_always "$REPO_RAW/mega-claude-prompt.md"          ".ralph/mega-claude-prompt.md"          "mega-claude-prompt.md"
download_always "$REPO_RAW/mega-ralph-convert-prompt.md"   ".ralph/mega-ralph-convert-prompt.md"   "mega-ralph-convert-prompt.md"
download_always "$REPO_RAW/mega-ralph-reflect-prompt.md"   ".ralph/mega-ralph-reflect-prompt.md"   "mega-ralph-reflect-prompt.md"

# ---------------------------------------------------------------------------
# Download skills (always overwrite)
# ---------------------------------------------------------------------------
echo ""
echo "Skills (.ralph/skills/):"
download_always "$REPO_RAW/skills/prd/SKILL.md"        ".ralph/skills/prd/SKILL.md"        "skills/prd/SKILL.md"
download_always "$REPO_RAW/skills/ralph/SKILL.md"      ".ralph/skills/ralph/SKILL.md"      "skills/ralph/SKILL.md"
download_always "$REPO_RAW/skills/masterplan/SKILL.md" ".ralph/skills/masterplan/SKILL.md" "skills/masterplan/SKILL.md"

# ---------------------------------------------------------------------------
# Append .ralph/ to project .gitignore (don't overwrite)
# ---------------------------------------------------------------------------
echo ""
grep -qxF '.ralph/' .gitignore 2>/dev/null || echo '.ralph/' >> .gitignore
echo "  [done] .gitignore (.ralph/ entry)"

# ---------------------------------------------------------------------------
# Remove old ralph.sh / mega-ralph.sh if present (v3 remnants)
# ---------------------------------------------------------------------------
rm -f ".ralph/ralph.sh" 2>/dev/null || true
rm -f ".ralph/mega-ralph.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Write VERSION
# ---------------------------------------------------------------------------
echo "$VERSION" > ".ralph/VERSION"

# ---------------------------------------------------------------------------
# Set permissions
# ---------------------------------------------------------------------------
chmod +x ".ralph/run.sh" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  Ralph v${VERSION} installed successfully!"
echo "================================================================"
echo ""
echo "  plans/                    - PRD & masterplan files (committed)"
echo "  .gitignore                - Has .ralph/ entry"
echo ""
echo "  .ralph/                   - Infrastructure (gitignored)"
echo "    run.sh                  - Unified entry point"
echo "    state/                  - Per-plan runtime state"
echo "    archive/                - Completed run archives"
echo "    skills/                 - Skill definitions"
echo ""
echo "Next steps:"
echo ""
echo "  Single feature:"
echo "    1. Create a PRD:        use /prd skill"
echo "    2. Convert to JSON:     use /ralph skill"
echo "    3. Run:                 .ralph/run.sh --tool claude"
echo ""
echo "  Multi-phase project:"
echo "    1. Create a masterplan: use /masterplan skill"
echo "    2. Run:                 .ralph/run.sh --plan M1 --tool claude"
echo ""
