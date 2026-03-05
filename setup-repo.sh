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
mkdir -p "$RALPH_DIR/.ralph/state"
mkdir -p "$RALPH_DIR/.ralph/archive"
mkdir -p "$RALPH_DIR/plans"

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

  cp -f "$RALPH_HOME/mega-ralph-reflect-prompt.md" "$RALPH_DIR/.ralph/mega-ralph-reflect-prompt.md"
  echo "  [done] mega-ralph-reflect-prompt.md"
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
echo "3.0.0" > "$RALPH_DIR/.ralph/VERSION"

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
echo "  2. Run: cd ralph && ./.ralph/mega-ralph.sh --plan M1 --tool claude"
else
echo "  1. Create a PRD: use Claude with the /prd skill"
echo "  2. Convert to prd.json: use Claude with the /ralph skill"
echo "  3. Run: cd ralph && ./.ralph/ralph.sh --tool claude"
fi
echo ""
echo "Tip: Add ralph/ to your repo so teammates can use the same setup."
echo ""
