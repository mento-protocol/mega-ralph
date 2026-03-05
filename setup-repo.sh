#!/bin/bash
# setup-repo.sh - Set up a repository for Ralph usage (from source)
#
# Run this script FROM INSIDE your target project repository to set it up
# with Ralph's autonomous agent tooling.
#
# Usage:
#   /path/to/ralph/setup-repo.sh

set -e

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --mega)
      # Accepted for backwards compat but ignored (always installs everything)
      shift
      ;;
    -h|--help)
      echo "Usage: setup-repo.sh"
      echo ""
      echo "Run from inside your target project repository."
      echo "Installs plans/ and .ralph/ at the project root."
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

VERSION="4.0.0"

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
echo "Setting up Ralph v${VERSION} in: $TARGET_DIR"
echo ""

mkdir -p ".ralph/skills/prd"
mkdir -p ".ralph/skills/ralph"
mkdir -p ".ralph/skills/masterplan"
mkdir -p ".ralph/state"
mkdir -p ".ralph/archive"
mkdir -p "plans"

# ---------------------------------------------------------------------------
# Copy infrastructure files (always overwrite)
# ---------------------------------------------------------------------------
echo "Infrastructure (.ralph/):"
cp -f "$RALPH_HOME/run.sh" ".ralph/run.sh"
chmod +x ".ralph/run.sh"
echo "  [done] run.sh"

cp -f "$RALPH_HOME/CLAUDE.md" ".ralph/CLAUDE.md"
echo "  [done] CLAUDE.md"

if [[ -f "$RALPH_HOME/prompt.md" ]]; then
  cp -f "$RALPH_HOME/prompt.md" ".ralph/prompt.md"
  echo "  [done] prompt.md"
fi

# ---------------------------------------------------------------------------
# Copy mega-ralph templates (always overwrite)
# ---------------------------------------------------------------------------
echo ""
echo "Mega-ralph templates (.ralph/):"

cp -f "$RALPH_HOME/mega-claude-prompt.md" ".ralph/mega-claude-prompt.md"
echo "  [done] mega-claude-prompt.md"

cp -f "$RALPH_HOME/mega-ralph-convert-prompt.md" ".ralph/mega-ralph-convert-prompt.md"
echo "  [done] mega-ralph-convert-prompt.md"

cp -f "$RALPH_HOME/mega-ralph-reflect-prompt.md" ".ralph/mega-ralph-reflect-prompt.md"
echo "  [done] mega-ralph-reflect-prompt.md"

# ---------------------------------------------------------------------------
# Copy skills (always overwrite)
# ---------------------------------------------------------------------------
echo ""
echo "Skills (.ralph/skills/):"
if [[ -d "$RALPH_HOME/skills" ]]; then
  cp -f "$RALPH_HOME/skills/prd/SKILL.md" ".ralph/skills/prd/SKILL.md"
  cp -f "$RALPH_HOME/skills/ralph/SKILL.md" ".ralph/skills/ralph/SKILL.md"
  cp -f "$RALPH_HOME/skills/masterplan/SKILL.md" ".ralph/skills/masterplan/SKILL.md"
  echo "  [done] skills/prd/SKILL.md"
  echo "  [done] skills/ralph/SKILL.md"
  echo "  [done] skills/masterplan/SKILL.md"
fi

# ---------------------------------------------------------------------------
# Append .ralph/ to project .gitignore
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
# Print instructions
# ---------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  Ralph v${VERSION} setup complete!"
echo "================================================================"
echo ""
echo "Directory structure:"
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
