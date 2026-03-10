#!/bin/bash
# run.sh - Unified Ralph entry point
#
# Usage:
#   .ralph/run.sh                                    # Auto-detect mode, run
#   .ralph/run.sh status                             # Rich status display
#   .ralph/run.sh switch                             # Interactive plan switcher
#   .ralph/run.sh --plan M1 --tool claude            # Run specific masterplan
#   .ralph/run.sh --tool claude --model sonnet 15    # Ralph mode with options
#   .ralph/run.sh --plan M1 --start-phase 5          # Resume mega mode from phase

set -e

# ---------------------------------------------------------------------------
# Signal handling - ensure Ctrl-C kills everything
# ---------------------------------------------------------------------------
OUTFILE=""
CHILD_PID=""

# Kill the entire process tree rooted at a given PID
kill_tree() {
  local pid="$1"
  # Find all descendants (children, grandchildren, etc.)
  local children
  children=$(ps -o pid= --ppid "$pid" 2>/dev/null || true)
  for child in $children; do
    kill_tree "$child"
  done
  kill -TERM "$pid" 2>/dev/null || true
}

cleanup() {
  echo ""
  echo "Interrupted."
  rm -f "$OUTFILE"
  # Remove trap to avoid recursion
  trap - INT TERM
  # Kill tracked child and its entire process tree
  if [[ -n "$CHILD_PID" ]]; then
    kill_tree "$CHILD_PID"
  fi
  # Also kill our process group as a safety net
  kill -- -$$ 2>/dev/null || kill 0 2>/dev/null || true
  exit 130
}
trap cleanup INT TERM

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

STATE_DIR="$SCRIPT_DIR/current"       # symlink to active state dir
PRD_FILE="$STATE_DIR/prd.json"
PROGRESS_FILE="$STATE_DIR/progress.txt"
LAST_BRANCH_FILE="$STATE_DIR/.last-branch"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
PLANS_DIR="$PROJECT_ROOT/plans"

PRD_PROMPT_TEMPLATE="$SCRIPT_DIR/mega-claude-prompt.md"
CONVERT_PROMPT_TEMPLATE="$SCRIPT_DIR/mega-ralph-convert-prompt.md"
REFLECT_PROMPT_TEMPLATE="$SCRIPT_DIR/mega-ralph-reflect-prompt.md"
REVIEW_PROMPT_TMPL="$SCRIPT_DIR/review-prompt.md"
REVIEW_FIXES_PROMPT_TMPL="$SCRIPT_DIR/review-fixes-prompt.md"
PHASE_REVIEW_PROMPT_TMPL="$SCRIPT_DIR/phase-review-prompt.md"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
show_help() {
  echo "Usage: run.sh [SUBCOMMAND] [OPTIONS] [max_iterations]"
  echo ""
  echo "Subcommands:"
  echo "  status                  Show current plan status"
  echo "  switch                  Interactive plan switcher"
  echo ""
  echo "Options:"
  echo "  --plan M1|FILE          Plan shorthand (M1) or file path"
  echo "  --start-phase N         Resume mega mode from phase N (default: 1)"
  echo "  --max-iterations-per-phase N  Max iterations per phase in mega mode (default: 25)"
  echo "  --tool amp|claude|codex AI tool to use (default: claude)"
  echo "  --model MODEL           Model to use (e.g., sonnet, opus)"
  echo "  --base BRANCH           Base branch for feature branches (skip interactive prompt)"
  echo "  --with-review           Enable code review after each story and phase"
  echo "  --review-tool TOOL      Tool for review (default: same as --tool)"
  echo "  --review-model MODEL    Model for review (default: same as --model)"
  echo "  -h, --help              Show this help"
  echo ""
  echo "When no --plan is given, auto-detects mode:"
  echo "  current/masterplan.json exists  -> mega mode (resume)"
  echo "  current/prd.json exists         -> ralph mode (iteration loop)"
  exit 0
}

# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

# Create branch from base if it doesn't exist, or switch to it if it does.
# No-op if already on correct branch.
git_ensure_branch() {
  local branch="$1"
  local base="$2"

  local current
  current=$(cd "$PROJECT_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  if [[ "$current" == "$branch" ]]; then
    return 0
  fi

  # Check if branch exists (local or remote)
  if (cd "$PROJECT_ROOT" && git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null); then
    echo "  Switching to existing branch: $branch"
    (cd "$PROJECT_ROOT" && git checkout "$branch")
  elif (cd "$PROJECT_ROOT" && git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null); then
    echo "  Checking out remote branch: $branch"
    (cd "$PROJECT_ROOT" && git checkout -b "$branch" "origin/$branch")
  else
    echo "  Creating branch: $branch (from $base)"
    (cd "$PROJECT_ROOT" && git checkout -b "$branch" "$base")
  fi
}

# Checkout target, merge source with --no-ff, checkout back.
# On conflict: error with clear message and exit.
git_merge_branch() {
  local source="$1"
  local target="$2"

  local current
  current=$(cd "$PROJECT_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  echo "  Merging $source → $target"
  (cd "$PROJECT_ROOT" && git checkout "$target")

  if ! (cd "$PROJECT_ROOT" && git merge --no-ff "$source" -m "merge: $source into $target"); then
    echo ""
    echo "Error: Merge conflict merging $source into $target"
    echo "Resolve conflicts manually and re-run."
    (cd "$PROJECT_ROOT" && git merge --abort 2>/dev/null || true)
    (cd "$PROJECT_ROOT" && git checkout "$current" 2>/dev/null || true)
    exit 1
  fi

  # Return to original branch if different
  if [[ "$current" != "$target" ]]; then
    (cd "$PROJECT_ROOT" && git checkout "$current")
  fi
}

# ---------------------------------------------------------------------------
# Base branch selection
# ---------------------------------------------------------------------------

# Interactive prompt for base branch selection.
# Sets BASE_BRANCH global. Skipped if --base was provided.
prompt_base_branch() {
  # If --base was given, use it directly
  if [[ -n "${ARG_BASE_BRANCH:-}" ]]; then
    BASE_BRANCH="$ARG_BASE_BRANCH"
    echo "  Base branch: $BASE_BRANCH (from --base)"
    return
  fi

  # On resume, load from stored config
  if [[ -n "${STORED_BASE_BRANCH:-}" ]]; then
    BASE_BRANCH="$STORED_BASE_BRANCH"
    echo "  Base branch: $BASE_BRANCH (from saved config)"
    return
  fi

  # Non-interactive (piped stdin): default to main
  if [[ ! -t 0 ]]; then
    BASE_BRANCH="main"
    echo "  Warning: Non-interactive mode, defaulting base branch to 'main'"
    return
  fi

  # Interactive prompt
  local current_branch
  current_branch=$(cd "$PROJECT_ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")

  echo ""
  echo "Base branch for feature branches:"
  echo "  1) main"
  if [[ "$current_branch" != "main" ]]; then
    echo "  2) $current_branch (current)"
    echo "  3) develop"
    echo "  4) other (enter branch name)"
    echo ""
    read -r -p "Select [1-4, default 1]: " selection
  else
    echo "  2) develop"
    echo "  3) other (enter branch name)"
    echo ""
    read -r -p "Select [1-3, default 1]: " selection
  fi

  case "${selection:-1}" in
    1)
      BASE_BRANCH="main"
      ;;
    2)
      if [[ "$current_branch" != "main" ]]; then
        BASE_BRANCH="$current_branch"
      else
        BASE_BRANCH="develop"
      fi
      ;;
    3)
      if [[ "$current_branch" != "main" ]]; then
        BASE_BRANCH="develop"
      else
        read -r -p "Enter branch name: " BASE_BRANCH
        if [[ -z "$BASE_BRANCH" ]]; then
          BASE_BRANCH="main"
        fi
      fi
      ;;
    4)
      read -r -p "Enter branch name: " BASE_BRANCH
      if [[ -z "$BASE_BRANCH" ]]; then
        BASE_BRANCH="main"
      fi
      ;;
    *)
      BASE_BRANCH="main"
      ;;
  esac

  echo "  Base branch: $BASE_BRANCH"
}

# ---------------------------------------------------------------------------
# Review turn runner
# ---------------------------------------------------------------------------

# Builds prompt from template with substitutions, invokes review tool.
# Non-fatal on failure (warning + continue).
#
# Usage: run_review_turn <template_file> <key1> <val1> [<key2> <val2> ...]
run_review_turn() {
  local template_file="$1"
  shift

  if [[ ! -f "$template_file" ]]; then
    echo "  Warning: Review template not found: $template_file (skipping review)"
    return 0
  fi

  local review_tool="${REVIEW_TOOL:-$TOOL}"
  local review_model="${REVIEW_MODEL:-$MODEL}"
  local review_model_args=""
  if [[ -n "$review_model" ]]; then
    review_model_args="--model $review_model"
  fi

  # Build prompt with key/value substitutions
  local prompt_file
  prompt_file=$(mktemp)
  cp "$template_file" "$prompt_file"

  while [[ $# -ge 2 ]]; do
    local key="$1"
    local val="$2"
    shift 2
    # Use sed for simple placeholder replacement
    # Escape sed special chars in val
    local escaped_val
    escaped_val=$(printf '%s\n' "$val" | sed 's/[&/\]/\\&/g')
    sed -i "s|${key}|${escaped_val}|g" "$prompt_file"
  done

  # Ensure reviews directory exists
  mkdir -p "$STATE_DIR/reviews"

  echo "  Running review ($review_tool)..."
  local exit_code=0
  if [[ "$review_tool" == "amp" ]]; then
    amp --dangerously-allow-all < "$prompt_file" >/dev/null 2>&1 &
  elif [[ "$review_tool" == "codex" ]]; then
    local codex_model_args=""
    if [[ -n "$review_model" ]]; then
      codex_model_args="--model $review_model"
    fi
    codex exec --full-auto $codex_model_args - < "$prompt_file" >/dev/null 2>&1 &
  else
    claude --dangerously-skip-permissions $review_model_args --print < "$prompt_file" >/dev/null 2>&1 &
  fi
  CHILD_PID=$!
  wait $CHILD_PID 2>/dev/null || exit_code=$?
  CHILD_PID=""

  rm -f "$prompt_file"

  if [[ $exit_code -ne 0 ]]; then
    echo "  Warning: Review failed (exit code $exit_code). Continuing without review."
    return 0
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
# STATUS SUBCOMMAND
# ═══════════════════════════════════════════════════════════════════════════
do_status() {
  echo ""
  echo "Ralph Status"
  echo "════════════════════════════════════════════"
  echo ""

  # Check if current symlink exists
  if [[ ! -L "$SCRIPT_DIR/current" ]]; then
    echo "  No active plan. Use /ralph or /masterplan skill to set one up."
    echo ""
    echo "════════════════════════════════════════════"
    exit 0
  fi

  # Determine plan ID from symlink target
  CURRENT_TARGET=$(readlink "$SCRIPT_DIR/current" 2>/dev/null || echo "")
  PLAN_ID=$(basename "$CURRENT_TARGET")

  # Read masterplan.json if exists (for mega-ralph plans)
  MASTERPLAN_FILE="$STATE_DIR/masterplan.json"
  if [[ -f "$MASTERPLAN_FILE" ]]; then
    PLAN_NAME=$(jq -r '.project // "Unknown"' "$MASTERPLAN_FILE" 2>/dev/null || echo "Unknown")
    TOTAL_PHASES=$(jq -r '.totalPhases // "?"' "$MASTERPLAN_FILE" 2>/dev/null || echo "?")
    CURRENT_PHASE=$(jq -r '.currentPhase // "?"' "$MASTERPLAN_FILE" 2>/dev/null || echo "?")
    PHASE_TITLE=$(jq -r --argjson p "${CURRENT_PHASE}" \
      '(.phases[] | select(.phase == $p) | .title) // "Unknown"' \
      "$MASTERPLAN_FILE" 2>/dev/null || echo "Unknown")
    echo "  Active Plan:  $PLAN_ID - $PLAN_NAME"
    echo "  Phase:        $CURRENT_PHASE of $TOTAL_PHASES ($PHASE_TITLE)"
  else
    echo "  Active Plan:  $PLAN_ID (standalone)"
  fi

  # Read branch from prd.json
  if [[ -f "$PRD_FILE" ]]; then
    BRANCH=$(jq -r '.branchName // "unknown"' "$PRD_FILE" 2>/dev/null || echo "unknown")
    echo "  Branch:       $BRANCH"
  fi

  echo ""

  # Stories status
  if [[ -f "$PRD_FILE" ]]; then
    TOTAL_STORIES=$(jq '.userStories | length' "$PRD_FILE" 2>/dev/null || echo "0")
    DONE_STORIES=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE" 2>/dev/null || echo "0")
    FIRST_PENDING=$(jq -r '[.userStories[] | select(.passes == false)][0].id // empty' "$PRD_FILE" 2>/dev/null || echo "")

    echo "  Stories:      $DONE_STORIES/$TOTAL_STORIES complete"

    # List each story with status marker
    jq -r --arg pending "$FIRST_PENDING" '.userStories[] |
      if .passes == true then "    \u2713 \(.id)  \(.title)"
      elif .id == $pending then "    \u2192 \(.id)  \(.title)"
      else "    \u00b7 \(.id)  \(.title)"
      end' "$PRD_FILE" 2>/dev/null
  else
    echo "  Stories:      No prd.json found"
  fi

  echo ""

  # Last commit
  LAST_COMMIT=$(cd "$PROJECT_ROOT" && git log --oneline -1 2>/dev/null || echo "(no commits)")
  LAST_TIME=$(cd "$PROJECT_ROOT" && git log -1 --format='%ar' 2>/dev/null || echo "")
  echo "  Last Commit:  $LAST_COMMIT${LAST_TIME:+ ($LAST_TIME)}"

  # Progress file location
  echo "  Progress:     $STATE_DIR/progress.txt"

  echo ""
  echo "════════════════════════════════════════════"
  exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# SWITCH SUBCOMMAND
# ═══════════════════════════════════════════════════════════════════════════
do_switch() {
  echo ""
  echo "Ralph Plans"
  echo "════════════════════════════════════════════"
  echo ""

  # Find all state directories
  local state_dirs=()
  local plan_ids=()
  local plan_names=()
  local plan_progress=()

  if [[ ! -d "$SCRIPT_DIR/state" ]]; then
    echo "  No plans found. Use /ralph or /masterplan skill to create one."
    echo ""
    exit 0
  fi

  local current_target=""
  if [[ -L "$SCRIPT_DIR/current" ]]; then
    current_target=$(readlink "$SCRIPT_DIR/current" 2>/dev/null || echo "")
    current_target=$(basename "$current_target")
  fi

  local idx=0
  for dir in "$SCRIPT_DIR"/state/*/; do
    [[ -d "$dir" ]] || continue
    local plan_id
    plan_id=$(basename "$dir")
    plan_ids+=("$plan_id")
    state_dirs+=("$dir")

    # Get plan name and progress
    local name="" progress_str=""
    if [[ -f "$dir/masterplan.json" ]]; then
      name=$(jq -r '.project // ""' "$dir/masterplan.json" 2>/dev/null || echo "")
      local total completed
      total=$(jq -r '.totalPhases // 0' "$dir/masterplan.json" 2>/dev/null || echo "0")
      completed=$(jq '[.phases[] | select(.status == "completed")] | length' "$dir/masterplan.json" 2>/dev/null || echo "0")
      progress_str="Phase $completed/$total"
    elif [[ -f "$dir/prd.json" ]]; then
      name=$(jq -r '.description // ""' "$dir/prd.json" 2>/dev/null || echo "")
      # Truncate long descriptions
      if [[ ${#name} -gt 40 ]]; then
        name="${name:0:37}..."
      fi
      local total done_count
      total=$(jq '.userStories | length' "$dir/prd.json" 2>/dev/null || echo "0")
      done_count=$(jq '[.userStories[] | select(.passes == true)] | length' "$dir/prd.json" 2>/dev/null || echo "0")
      if [[ "$done_count" -eq "$total" && "$total" -gt 0 ]]; then
        progress_str="complete"
      elif [[ "$done_count" -eq 0 ]]; then
        progress_str="not started"
      else
        progress_str="$done_count/$total stories"
      fi
    else
      progress_str="empty"
    fi

    plan_names+=("$name")
    plan_progress+=("$progress_str")

    idx=$((idx + 1))
  done

  if [[ ${#plan_ids[@]} -eq 0 ]]; then
    echo "  No plans found."
    echo ""
    exit 0
  fi

  # Display plans
  for i in "${!plan_ids[@]}"; do
    local marker="  "
    if [[ "${plan_ids[$i]}" == "$current_target" ]]; then
      marker="→ "
    fi
    local num=$((i + 1))
    local display="${plan_ids[$i]}"
    if [[ -n "${plan_names[$i]}" ]]; then
      display="$display  ${plan_names[$i]}"
    fi
    if [[ -n "${plan_progress[$i]}" ]]; then
      display="$display (${plan_progress[$i]})"
    fi
    printf "  %d. %s%s\n" "$num" "$marker" "$display"
  done

  echo ""

  # Prompt for selection
  read -r -p "Select plan [1-${#plan_ids[@]}]: " selection

  if [[ -z "$selection" ]]; then
    echo "No selection made."
    exit 0
  fi

  if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#plan_ids[@]} ]]; then
    echo "Invalid selection."
    exit 1
  fi

  local selected_idx=$((selection - 1))
  local selected_id="${plan_ids[$selected_idx]}"

  ln -sfn "state/$selected_id" "$SCRIPT_DIR/current"
  echo ""
  echo "Switched to $selected_id${plan_names[$selected_idx]:+ (${plan_names[$selected_idx]})}"
  exit 0
}

# ═══════════════════════════════════════════════════════════════════════════
# RALPH MODE — iteration loop
# ═══════════════════════════════════════════════════════════════════════════
run_ralph() {
  local max_iterations="$1"
  local tool="$2"
  local model="$3"

  # Build model args for claude/codex CLI
  local claude_model_args=""
  local codex_model_args=""
  if [[ -n "$model" ]]; then
    claude_model_args="--model $model"
    codex_model_args="--model $model"
  fi

  # Ensure state directory exists (via current symlink)
  if [[ ! -L "$SCRIPT_DIR/current" ]]; then
    mkdir -p "$SCRIPT_DIR/state/default"
    ln -sfn "state/default" "$SCRIPT_DIR/current"
  fi

  # Ensure the target of current exists
  mkdir -p "$STATE_DIR"

  # Branch setup for standalone ralph mode (not called from run_mega)
  if [[ -z "${PLAN_ID:-}" ]]; then
    # Load stored base branch if resuming
    local branch_config="$STATE_DIR/.branch-config"
    if [[ -f "$branch_config" ]]; then
      STORED_BASE_BRANCH=$(grep '^base=' "$branch_config" 2>/dev/null | cut -d= -f2)
    fi

    prompt_base_branch

    # Save branch config for resume
    echo "base=$BASE_BRANCH" > "$branch_config"

    # Set up the feature branch if prd.json has a branchName
    if [[ -f "$PRD_FILE" ]]; then
      local feature_branch
      feature_branch=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
      if [[ -n "$feature_branch" ]]; then
        git_ensure_branch "$feature_branch" "$BASE_BRANCH"
      fi
    fi
  fi

  # Archive previous run if branch changed
  if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
    local current_branch last_branch
    current_branch=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
    last_branch=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

    if [ -n "$current_branch" ] && [ -n "$last_branch" ] && [ "$current_branch" != "$last_branch" ]; then
      local date_str folder_name archive_folder
      date_str=$(date +%Y-%m-%d)
      folder_name=$(echo "$last_branch" | sed 's|^feat/||' | sed 's|^ralph/||')
      archive_folder="$ARCHIVE_DIR/$date_str-$folder_name"

      echo "Archiving previous run: $last_branch"
      mkdir -p "$archive_folder"
      [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$archive_folder/"
      [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$archive_folder/"
      echo "   Archived to: $archive_folder"

      echo "# Ralph Progress Log" > "$PROGRESS_FILE"
      echo "Started: $(date)" >> "$PROGRESS_FILE"
      echo "---" >> "$PROGRESS_FILE"
    fi
  fi

  # Track current branch
  if [ -f "$PRD_FILE" ]; then
    local current_branch
    current_branch=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
    if [ -n "$current_branch" ]; then
      echo "$current_branch" > "$LAST_BRANCH_FILE"
    fi
  fi

  # Initialize progress file if it doesn't exist
  if [ ! -f "$PROGRESS_FILE" ]; then
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi

  if [[ -n "$model" ]]; then
    echo "Starting Ralph - Tool: $tool - Model: $model - Max iterations: $max_iterations"
  else
    echo "Starting Ralph - Tool: $tool - Max iterations: $max_iterations"
  fi
  if [[ "${WITH_REVIEW:-false}" == "true" ]]; then
    echo "  Review: enabled (tool: ${REVIEW_TOOL:-$tool}, model: ${REVIEW_MODEL:-${model:-default}})"
  fi
  echo "Interjection: echo 'your notes' > $STATE_DIR/interjection.md"

  # Exponential backoff settings
  local backoff=5
  local max_backoff=300

  # Review templates
  local REVIEW_PROMPT_TEMPLATE="$SCRIPT_DIR/review-prompt.md"
  local REVIEW_FIXES_PROMPT_TEMPLATE="$SCRIPT_DIR/review-fixes-prompt.md"

  for i in $(seq 1 "$max_iterations"); do
    echo ""
    echo "==============================================================="
    echo "  Ralph Iteration $i of $max_iterations ($tool)"
    echo "==============================================================="

    # Snapshot passed stories before iteration (for review detection)
    local pre_passed_ids=""
    if [[ "${WITH_REVIEW:-false}" == "true" && -f "$PRD_FILE" ]]; then
      pre_passed_ids=$(jq -r '[.userStories[] | select(.passes == true) | .id] | join(",")' "$PRD_FILE" 2>/dev/null || echo "")
    fi

    # Check for interjection file
    local interjection_file="$STATE_DIR/interjection.md"
    local interjection=""
    if [[ -f "$interjection_file" ]] && [[ -s "$interjection_file" ]]; then
      interjection=$(cat "$interjection_file")
      echo ""
      echo "  ** Interjection detected — incorporating user notes **"
      echo ""
      > "$interjection_file"
    fi

    # Build the prompt
    local prompt_file
    prompt_file=$(mktemp)
    local base_prompt
    if [[ "$tool" == "amp" ]]; then
      base_prompt="$SCRIPT_DIR/prompt.md"
    else
      base_prompt="$SCRIPT_DIR/CLAUDE.md"
    fi

    if [[ -n "$interjection" ]]; then
      printf '## IMPORTANT — User Interjection\n\nThe user has added the following notes before this iteration. Take these into account and prioritize them:\n\n%s\n\n---\n\n' "$interjection" > "$prompt_file"
      cat "$base_prompt" >> "$prompt_file"
    else
      cp "$base_prompt" "$prompt_file"
    fi

    # Run the tool
    local exit_code=0
    if [[ "$tool" == "amp" ]]; then
      amp --dangerously-allow-all < "$prompt_file" >/dev/null 2>&1 &
    elif [[ "$tool" == "codex" ]]; then
      codex exec --full-auto $codex_model_args - < "$prompt_file" >/dev/null 2>&1 &
    else
      claude --dangerously-skip-permissions $claude_model_args --print < "$prompt_file" >/dev/null 2>&1 &
    fi
    CHILD_PID=$!
    wait $CHILD_PID 2>/dev/null || exit_code=$?
    CHILD_PID=""
    rm -f "$prompt_file"

    # Exit immediately on SIGINT/SIGTERM
    if [[ $exit_code -eq 130 || $exit_code -eq 143 ]]; then
      echo ""
      echo "Interrupted."
      exit $exit_code
    fi

    # Check if all stories are done by reading prd.json directly
    if [[ -f "$PRD_FILE" ]]; then
      local remaining
      remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE" 2>/dev/null || echo "1")
      if [[ "$remaining" -eq 0 ]]; then
        echo ""
        echo "Ralph completed all tasks!"
        echo "Completed at iteration $i of $max_iterations"
        return 0
      fi
    fi

    # Check for errors and apply exponential backoff
    if [[ $exit_code -ne 0 ]]; then
      echo ""
      echo "Error on iteration $i (exit code $exit_code). Retrying in ${backoff}s..."
      sleep "$backoff"
      backoff=$((backoff * 2))
      if [[ $backoff -gt $max_backoff ]]; then
        backoff=$max_backoff
      fi
      continue
    fi

    # Reset backoff on success
    backoff=5

    # Per-story review: detect if a new story passed in this iteration
    if [[ "${WITH_REVIEW:-false}" == "true" && -f "$PRD_FILE" && -f "$REVIEW_PROMPT_TEMPLATE" ]]; then
      local post_passed_ids
      post_passed_ids=$(jq -r '[.userStories[] | select(.passes == true) | .id] | join(",")' "$PRD_FILE" 2>/dev/null || echo "")

      if [[ "$post_passed_ids" != "$pre_passed_ids" ]]; then
        # Find newly passed story IDs
        local new_ids=""
        IFS=',' read -ra post_arr <<< "$post_passed_ids"
        IFS=',' read -ra pre_arr <<< "$pre_passed_ids"
        for pid in "${post_arr[@]}"; do
          local found=false
          for ppid in "${pre_arr[@]}"; do
            if [[ "$pid" == "$ppid" ]]; then
              found=true
              break
            fi
          done
          if [[ "$found" == "false" && -n "$pid" ]]; then
            new_ids="$pid"
            break  # Review the first newly passed story
          fi
        done

        if [[ -n "$new_ids" ]]; then
          local story_title
          story_title=$(jq -r --arg id "$new_ids" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE" 2>/dev/null || echo "")
          local review_doc="$STATE_DIR/reviews/review-${new_ids}.md"

          echo ""
          echo "  ── Per-story review: $new_ids ──"

          # Review turn
          run_review_turn "$REVIEW_PROMPT_TEMPLATE" \
            "{{STORY_ID}}" "$new_ids" \
            "{{STORY_TITLE}}" "$story_title" \
            "{{REVIEW_DOC_PATH}}" "$review_doc"

          # Fixes turn (only if review doc was created)
          if [[ -f "$review_doc" ]] && grep -q "NEEDS-FIXES" "$review_doc" 2>/dev/null; then
            echo "  Review verdict: NEEDS-FIXES — running fixes..."
            run_review_turn "$REVIEW_FIXES_PROMPT_TEMPLATE" \
              "{{STORY_ID}}" "$new_ids" \
              "{{REVIEW_DOC_PATH}}" "$review_doc"
          elif [[ -f "$review_doc" ]]; then
            echo "  Review verdict: PASS"
          fi

          echo "  ── Review complete ──"
          echo ""
        fi
      fi
    fi

    echo "Iteration $i complete. Continuing..."
    sleep 2
  done

  echo ""
  echo "Ralph reached max iterations ($max_iterations) without completing all tasks."
  echo "Check $PROGRESS_FILE for status."
  return 1
}

# ═══════════════════════════════════════════════════════════════════════════
# MEGA MODE — multi-phase orchestrator
# ═══════════════════════════════════════════════════════════════════════════

# ---------------------------------------------------------------------------
# Parse the master plan to extract phases
# ---------------------------------------------------------------------------
parse_phases() {
  local plan_file="$1"
  local phases_json="[]"
  local current_phase=""
  local current_title=""
  local current_desc=""
  local in_phase=false

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^##[[:space:]]+[Pp]hase[[:space:]]+([0-9]+)[[:space:]]*[:.]+[[:space:]]*(.*)|^##[[:space:]]+[Pp]hase[[:space:]]+([0-9]+)[[:space:]]*[-]+[[:space:]]+(.*) ]]; then
      if [[ -n "${BASH_REMATCH[1]}" ]]; then
        _phase="${BASH_REMATCH[1]}"
        _title="${BASH_REMATCH[2]}"
      else
        _phase="${BASH_REMATCH[3]}"
        _title="${BASH_REMATCH[4]}"
      fi
      if $in_phase && [[ -n "$current_phase" ]]; then
        current_desc=$(echo "$current_desc" | sed 's/[[:space:]]*$//')
        phases_json=$(echo "$phases_json" | jq \
          --arg num "$current_phase" \
          --arg title "$current_title" \
          --arg desc "$current_desc" \
          '. + [{"phase": ($num | tonumber), "title": $title, "description": $desc}]')
      fi
      current_phase="$_phase"
      current_title="$_title"
      current_desc=""
      in_phase=true
    elif $in_phase; then
      if [[ -n "$current_desc" ]]; then
        current_desc="$current_desc
$line"
      else
        if [[ -n "$line" ]]; then
          current_desc="$line"
        fi
      fi
    fi
  done < "$plan_file"

  if $in_phase && [[ -n "$current_phase" ]]; then
    current_desc=$(echo "$current_desc" | sed 's/[[:space:]]*$//')
    phases_json=$(echo "$phases_json" | jq \
      --arg num "$current_phase" \
      --arg title "$current_title" \
      --arg desc "$current_desc" \
      '. + [{"phase": ($num | tonumber), "title": $title, "description": $desc}]')
  fi

  echo "$phases_json"
}

# ---------------------------------------------------------------------------
# Initialize or load masterplan.json
# ---------------------------------------------------------------------------
init_progress() {
  local total_phases="$1"
  local project_name
  project_name=$(basename "$PROJECT_ROOT" | sed 's/[^a-zA-Z0-9_-]/-/g')

  if [[ -f "$MEGA_PROGRESS" ]]; then
    echo "Resuming from existing masterplan.json"
    return
  fi

  cat > "$MEGA_PROGRESS" <<EOJSON
{
  "project": "$project_name",
  "masterPlan": "$(basename "$PLAN_PATH")",
  "totalPhases": $total_phases,
  "currentPhase": $START_PHASE,
  "phases": []
}
EOJSON

  echo "Created masterplan.json for $total_phases phases"
}

# ---------------------------------------------------------------------------
# Update masterplan.json
# ---------------------------------------------------------------------------
update_progress_start() {
  local phase_num="$1"
  local phase_title="$2"
  local branch_name="$3"
  local started_at
  started_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local existing
  existing=$(jq --argjson p "$phase_num" '.phases[] | select(.phase == $p)' "$MEGA_PROGRESS" 2>/dev/null || echo "")

  if [[ -n "$existing" ]]; then
    jq --argjson p "$phase_num" \
       --arg status "in_progress" \
       --arg started "$started_at" \
       --arg branch "$branch_name" \
       '(.phases[] | select(.phase == $p)) |= . + {
         "status": $status,
         "startedAt": $started,
         "branch": $branch
       } | .currentPhase = $p' "$MEGA_PROGRESS" > "$MEGA_PROGRESS.tmp" && mv "$MEGA_PROGRESS.tmp" "$MEGA_PROGRESS"
  else
    jq --argjson p "$phase_num" \
       --arg title "$phase_title" \
       --arg status "in_progress" \
       --arg started "$started_at" \
       --arg branch "$branch_name" \
       '.phases += [{
         "phase": $p,
         "title": $title,
         "status": $status,
         "startedAt": $started,
         "completedAt": null,
         "iterations": 0,
         "branch": $branch
       }] | .currentPhase = $p' "$MEGA_PROGRESS" > "$MEGA_PROGRESS.tmp" && mv "$MEGA_PROGRESS.tmp" "$MEGA_PROGRESS"
  fi
}

update_progress_complete() {
  local phase_num="$1"
  local iterations="$2"
  local completed_at
  completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  jq --argjson p "$phase_num" \
     --arg status "completed" \
     --arg completed "$completed_at" \
     --argjson iters "$iterations" \
     '(.phases[] | select(.phase == $p)) |= . + {
       "status": $status,
       "completedAt": $completed,
       "iterations": $iters
     }' "$MEGA_PROGRESS" > "$MEGA_PROGRESS.tmp" && mv "$MEGA_PROGRESS.tmp" "$MEGA_PROGRESS"
}

update_progress_failed() {
  local phase_num="$1"
  local iterations="$2"

  jq --argjson p "$phase_num" \
     --arg status "failed" \
     --argjson iters "$iterations" \
     '(.phases[] | select(.phase == $p)) |= . + {
       "status": $status,
       "iterations": $iters
     }' "$MEGA_PROGRESS" > "$MEGA_PROGRESS.tmp" && mv "$MEGA_PROGRESS.tmp" "$MEGA_PROGRESS"
}

# ---------------------------------------------------------------------------
# Get previous phases summary
# ---------------------------------------------------------------------------
get_previous_phases_summary() {
  local current_phase="$1"
  local summary=""

  if [[ "$current_phase" -le 1 ]]; then
    echo "This is the first phase. No previous phases."
    return
  fi

  local completed_phases
  completed_phases=$(jq -r --argjson p "$current_phase" \
    '.phases[] | select(.phase < $p and .status == "completed") | "Phase \(.phase): \(.title) [branch: \(.branch)]"' \
    "$MEGA_PROGRESS" 2>/dev/null || echo "")

  if [[ -n "$completed_phases" ]]; then
    summary="Completed phases:
$completed_phases
"
  fi

  local git_log
  git_log=$(cd "$PROJECT_ROOT" && git log --oneline -30 2>/dev/null || echo "(no git history available)")

  if [[ -n "$git_log" ]]; then
    summary="${summary}
Recent git history:
$git_log"
  fi

  echo "$summary"
}

# ---------------------------------------------------------------------------
# Generate a branch name from phase number and title
# ---------------------------------------------------------------------------
make_branch_name() {
  local phase_num="$1"
  local phase_title="$2"

  local slug
  slug=$(echo "$phase_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

  # In mega mode: feat/M<idx>-P<padded>-<slug>
  # In ralph mode: feat/<slug>
  if [[ -n "${PLAN_ID:-}" ]]; then
    printf "feat/%s-P%02d-%s" "$PLAN_ID" "$phase_num" "$slug"
  else
    printf "feat/%s" "$slug"
  fi
}

# Generate the top-level mega feature branch name
make_mega_branch_name() {
  local plan_idx="$1"
  local project_name="$2"

  local slug
  slug=$(echo "$project_name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')

  printf "feat/M%s-%s" "$plan_idx" "$slug"
}

# ---------------------------------------------------------------------------
# Build a prompt by replacing placeholders in a template
# ---------------------------------------------------------------------------
build_prompt() {
  local template_file="$1"
  local phase_number="$2"
  local phase_title="$3"
  local phase_description="$4"
  local previous_summary="$5"
  local project_name="$6"
  local prd_file="${7:-}"
  local prd_filename="${8:-}"
  local branch_name="${9:-}"

  local output_file
  output_file=$(mktemp)

  local plan_file_tmp desc_file summary_file prd_file_tmp
  plan_file_tmp=$(mktemp)
  desc_file=$(mktemp)
  summary_file=$(mktemp)
  prd_file_tmp=$(mktemp)

  cat "$PLAN_PATH" > "$plan_file_tmp"
  printf '%s' "$phase_description" > "$desc_file"
  printf '%s' "$previous_summary" > "$summary_file"
  printf '%s' "$prd_file" > "$prd_file_tmp"

  python3 -c "
import sys
template = open('$template_file').read()
replacements = {
    '{{PHASE_NUMBER}}': '$phase_number',
    '{{PHASE_TITLE}}': '$phase_title',
    '{{PROJECT_NAME}}': '$project_name',
    '{{PRD_FILENAME}}': '$prd_filename',
    '{{BRANCH_NAME}}': '$branch_name',
    '{{MASTER_PLAN}}': open('$plan_file_tmp').read(),
    '{{PHASE_DESCRIPTION}}': open('$desc_file').read(),
    '{{PREVIOUS_PHASES_SUMMARY}}': open('$summary_file').read(),
    '{{PRD_FILE}}': open('$prd_file_tmp').read().strip(),
}
for key, val in replacements.items():
    template = template.replace(key, val)
sys.stdout.write(template)
" > "$output_file"

  cat "$output_file"
  rm -f "$output_file" "$plan_file_tmp" "$desc_file" "$summary_file" "$prd_file_tmp"
}

# ---------------------------------------------------------------------------
# Archive a completed phase
# ---------------------------------------------------------------------------
archive_phase() {
  local phase_num="$1"
  local phase_title="$2"
  local branch_name="$3"

  local date_str
  date_str=$(date +%Y-%m-%d)
  local folder_name
  folder_name=$(echo "$branch_name" | sed 's|^feat/||' | sed 's|^ralph/||')
  local archive_path="$ARCHIVE_DIR/$date_str-$folder_name"

  echo "Archiving phase $phase_num: $phase_title"
  mkdir -p "$archive_path"

  [[ -f "$STATE_DIR/prd.json" ]] && cp "$STATE_DIR/prd.json" "$archive_path/"
  [[ -f "$STATE_DIR/progress.txt" ]] && cp "$STATE_DIR/progress.txt" "$archive_path/"

  # Archive reviews if present
  if [[ -d "$STATE_DIR/reviews" ]] && ls "$STATE_DIR/reviews/"*.md &>/dev/null; then
    mkdir -p "$archive_path/reviews"
    cp "$STATE_DIR/reviews/"*.md "$archive_path/reviews/" 2>/dev/null || true
    rm -rf "$STATE_DIR/reviews"
  fi

  local padded_phase
  padded_phase=$(printf '%02d' "$phase_num")
  local prd_pattern="$PLANS_DIR/"*"-${PLAN_ID}-P${padded_phase}-"*.md
  for f in $prd_pattern; do
    [[ -f "$f" ]] && cp "$f" "$archive_path/"
  done

  echo "  Archived to: $archive_path"

  rm -f "$STATE_DIR/prd.json"
  rm -f "$STATE_DIR/.last-branch"
  echo "# Ralph Progress Log" > "$STATE_DIR/progress.txt"
  echo "Started: $(date)" >> "$STATE_DIR/progress.txt"
  echo "---" >> "$STATE_DIR/progress.txt"
}

# ---------------------------------------------------------------------------
# Reflect on phase learnings and update master plan
# ---------------------------------------------------------------------------
reflect_and_update_plan() {
  local phase_num="$1"
  local phase_title="$2"
  local project_name="$3"
  local claude_model_args="$4"

  echo "  Reflecting on Phase $phase_num learnings and updating master plan..."

  local progress_content=""
  if [[ -f "$STATE_DIR/progress.txt" ]]; then
    progress_content=$(cat "$STATE_DIR/progress.txt")
  fi

  if [[ -z "$progress_content" || "$progress_content" == "# Ralph Progress Log"* && $(wc -l < "$STATE_DIR/progress.txt") -le 3 ]]; then
    echo "  No meaningful learnings to reflect on. Skipping."
    return 0
  fi

  if [[ ! -f "$REFLECT_PROMPT_TEMPLATE" ]]; then
    echo "  Warning: Reflect prompt template not found at $REFLECT_PROMPT_TEMPLATE. Skipping."
    return 0
  fi

  local prompt_file
  prompt_file=$(mktemp)

  local plan_file_tmp progress_file_tmp
  plan_file_tmp=$(mktemp)
  progress_file_tmp=$(mktemp)

  cat "$PLAN_PATH" > "$plan_file_tmp"
  printf '%s' "$progress_content" > "$progress_file_tmp"

  python3 -c "
import sys
template = open('$REFLECT_PROMPT_TEMPLATE').read()
replacements = {
    '{{PHASE_NUMBER}}': '$phase_num',
    '{{PHASE_TITLE}}': '$phase_title',
    '{{PROJECT_NAME}}': '$project_name',
    '{{PLAN_PATH}}': '$PLAN_PATH',
    '{{MASTER_PLAN}}': open('$plan_file_tmp').read(),
    '{{PHASE_PROGRESS}}': open('$progress_file_tmp').read(),
}
for key, val in replacements.items():
    template = template.replace(key, val)
sys.stdout.write(template)
" > "$prompt_file"

  local output_tmp
  output_tmp=$(mktemp)
  claude --dangerously-skip-permissions $claude_model_args --print < "$prompt_file" > "$output_tmp" 2>&1 &
  CHILD_PID=$!
  local reflect_exit=0
  wait $CHILD_PID 2>/dev/null || reflect_exit=$?
  CHILD_PID=""

  if [[ $reflect_exit -ne 0 ]]; then
    echo "  Warning: Claude failed to reflect on phase $phase_num (non-fatal, continuing)"
    rm -f "$prompt_file" "$plan_file_tmp" "$progress_file_tmp" "$output_tmp"
    return 0
  fi

  rm -f "$prompt_file" "$plan_file_tmp" "$progress_file_tmp" "$output_tmp"
  echo "  Master plan updated with Phase $phase_num learnings."
}

# ---------------------------------------------------------------------------
# Generate a PRD for a single phase using Claude
# ---------------------------------------------------------------------------
generate_phase_prd() {
  local phase_num="$1"
  local phase_title="$2"
  local phase_description="$3"
  local previous_summary="$4"
  local project_name="$5"
  local claude_model_args="$6"

  local padded_phase
  padded_phase=$(printf '%02d' "$phase_num")
  local title_slug
  title_slug=$(echo "$phase_title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//')
  local date_str
  date_str=$(date +%Y-%m-%d)
  local prd_filename="${date_str}-${PLAN_ID}-P${padded_phase}-${title_slug}.md"
  local prd_path="$PLANS_DIR/$prd_filename"

  if [[ -f "$prd_path" ]]; then
    echo "  PRD already exists: $prd_path (skipping generation)" >&2
    echo "$prd_path"
    return
  fi

  echo "  Generating PRD for Phase $phase_num: $phase_title ..." >&2

  mkdir -p "$PLANS_DIR"

  local prompt
  prompt=$(build_prompt "$PRD_PROMPT_TEMPLATE" "$phase_num" "$phase_title" "$phase_description" "$previous_summary" "$project_name" "" "$prd_filename")

  local output_tmp
  output_tmp=$(mktemp)

  # Write prompt to temp file for stdin redirect (avoids arg length limits)
  local prompt_tmp
  prompt_tmp=$(mktemp)
  printf '%s' "$prompt" > "$prompt_tmp"

  claude --dangerously-skip-permissions $claude_model_args --print < "$prompt_tmp" > "$output_tmp" 2>&1 &
  CHILD_PID=$!
  local gen_exit=0
  wait $CHILD_PID 2>/dev/null || gen_exit=$?
  CHILD_PID=""
  rm -f "$prompt_tmp"

  if [[ $gen_exit -ne 0 ]]; then
    echo "Error: Claude failed to generate PRD for phase $phase_num" >&2
    cat "$output_tmp" >&2
    rm -f "$output_tmp"
    return 1
  fi

  if [[ ! -f "$prd_path" ]]; then
    cp "$output_tmp" "$prd_path"
    echo "  PRD saved (from stdout fallback): $prd_path" >&2
  else
    echo "  PRD generated: $prd_path" >&2
  fi

  rm -f "$output_tmp"
  echo "$prd_path"
}

# ---------------------------------------------------------------------------
# Convert a phase PRD to prd.json using Claude
# ---------------------------------------------------------------------------
convert_prd_to_json() {
  local prd_path="$1"
  local phase_num="$2"
  local phase_title="$3"
  local project_name="$4"
  local claude_model_args="$5"
  local branch_name="${6:-}"

  echo "  Converting PRD to prd.json ..."

  rm -f "$STATE_DIR/prd.json"

  local prompt
  prompt=$(build_prompt "$CONVERT_PROMPT_TEMPLATE" "$phase_num" "$phase_title" "" "" "$project_name" "$prd_path" "" "$branch_name")

  local output_tmp prompt_tmp
  output_tmp=$(mktemp)
  prompt_tmp=$(mktemp)
  printf '%s' "$prompt" > "$prompt_tmp"

  claude --dangerously-skip-permissions $claude_model_args --print < "$prompt_tmp" > "$output_tmp" 2>&1 &
  CHILD_PID=$!
  local conv_exit=0
  wait $CHILD_PID 2>/dev/null || conv_exit=$?
  CHILD_PID=""
  rm -f "$prompt_tmp"

  if [[ $conv_exit -ne 0 ]]; then
    echo "Error: Claude failed to convert PRD to prd.json"
    cat "$output_tmp"
    rm -f "$output_tmp"
    return 1
  fi
  rm -f "$output_tmp"

  if [[ ! -f "$STATE_DIR/prd.json" ]]; then
    echo "Error: prd.json was not created after conversion"
    return 1
  fi

  if ! jq empty "$STATE_DIR/prd.json" 2>/dev/null; then
    echo "Error: prd.json is not valid JSON"
    return 1
  fi

  local pending_stories
  pending_stories=$(jq '[.userStories[] | select(.passes == false)] | length' "$STATE_DIR/prd.json" 2>/dev/null || echo "0")
  if [[ "$pending_stories" -eq 0 ]]; then
    echo "Error: prd.json has no stories with passes: false — conversion likely failed"
    return 1
  fi

  echo "  prd.json created successfully ($pending_stories stories)"
}

# ---------------------------------------------------------------------------
# run_mega — multi-phase orchestrator
# ---------------------------------------------------------------------------
run_mega() {
  local plan_file="$1"
  local start_phase="$2"
  local max_iterations="$3"
  local tool="$4"
  local model="$5"

  local claude_model_args=""
  if [[ -n "$model" ]]; then
    claude_model_args="--model $model"
  fi

  # ---------------------------------------------------------------------------
  # Resolve plan file and extract M-index
  # ---------------------------------------------------------------------------
  if [[ -z "$plan_file" ]]; then
    plan_file=$(ls "$PLANS_DIR/"*-M*-*.md 2>/dev/null | grep -v '\-P[0-9]' | tail -1 || echo "")
    if [[ -z "$plan_file" ]]; then
      if [[ -f "$PROJECT_ROOT/MASTER_PLAN.md" ]]; then
        plan_file="$PROJECT_ROOT/MASTER_PLAN.md"
        PLAN_IDX="1"
        PLAN_ID="M1"
      else
        echo "Error: No masterplan found in $PLANS_DIR/"
        echo "Create one with the /masterplan skill or specify with --plan"
        return 1
      fi
    fi
  fi

  if [[ "$plan_file" =~ ^M([0-9]+)$ ]]; then
    PLAN_IDX="${BASH_REMATCH[1]}"
    PLAN_ID="M${PLAN_IDX}"
    plan_file=$(ls "$PLANS_DIR/"*"-M${PLAN_IDX}-"*.md 2>/dev/null | grep -v '\-P[0-9]' | head -1 || echo "")
    if [[ -z "$plan_file" ]]; then
      echo "Error: No masterplan found matching M${PLAN_IDX} in $PLANS_DIR/"
      return 1
    fi
  else
    if [[ ! -f "$plan_file" ]]; then
      if [[ -f "$PROJECT_ROOT/$plan_file" ]]; then
        plan_file="$PROJECT_ROOT/$plan_file"
      else
        echo "Error: Plan file not found: $plan_file"
        return 1
      fi
    fi
    PLAN_IDX=$(basename "$plan_file" | grep -oP 'M\K[0-9]+' || echo "")
    if [[ -z "$PLAN_IDX" ]]; then
      PLAN_IDX="1"
    fi
    PLAN_ID="M${PLAN_IDX}"
  fi

  PLAN_PATH="$plan_file"

  # Per-plan state directory
  STATE_DIR="$SCRIPT_DIR/state/$PLAN_ID"
  mkdir -p "$STATE_DIR"
  ln -sfn "state/$PLAN_ID" "$SCRIPT_DIR/current"

  # Re-set dependent paths after STATE_DIR change
  PRD_FILE="$STATE_DIR/prd.json"
  PROGRESS_FILE="$STATE_DIR/progress.txt"
  LAST_BRANCH_FILE="$STATE_DIR/.last-branch"

  MEGA_PROGRESS="$STATE_DIR/masterplan.json"

  # Validate dependencies
  if [[ ! -f "$PRD_PROMPT_TEMPLATE" ]]; then
    echo "Error: PRD prompt template not found at $PRD_PROMPT_TEMPLATE"
    return 1
  fi

  if [[ ! -f "$CONVERT_PROMPT_TEMPLATE" ]]; then
    echo "Error: Conversion prompt template not found at $CONVERT_PROMPT_TEMPLATE"
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed."
    return 1
  fi

  if ! command -v claude &>/dev/null; then
    echo "Error: claude CLI is required but not installed."
    return 1
  fi

  if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required but not installed (used for template expansion)."
    return 1
  fi

  # ---------------------------------------------------------------------------
  # Base branch selection
  # ---------------------------------------------------------------------------
  # Load stored base branch from masterplan.json if resuming
  if [[ -f "$MEGA_PROGRESS" ]]; then
    STORED_BASE_BRANCH=$(jq -r '.baseBranch // empty' "$MEGA_PROGRESS" 2>/dev/null || echo "")
  fi

  prompt_base_branch

  # Parse the master plan (needed for project_name before header)
  local project_name
  project_name=$(basename "$PROJECT_ROOT" | sed 's/[^a-zA-Z0-9_-]/-/g')

  # ---------------------------------------------------------------------------
  # Masterplan feature branch
  # ---------------------------------------------------------------------------
  local mega_feature_branch
  mega_feature_branch=$(make_mega_branch_name "$PLAN_IDX" "$project_name")

  # Store in masterplan.json (or load existing)
  if [[ -f "$MEGA_PROGRESS" ]]; then
    local stored_feature_branch
    stored_feature_branch=$(jq -r '.featureBranch // empty' "$MEGA_PROGRESS" 2>/dev/null || echo "")
    if [[ -n "$stored_feature_branch" ]]; then
      mega_feature_branch="$stored_feature_branch"
    fi
  fi

  git_ensure_branch "$mega_feature_branch" "$BASE_BRANCH"

  echo ""
  echo "================================================================"
  echo "  MEGA-RALPH - Multi-Phase Project Orchestrator"
  echo "================================================================"
  echo "  Plan:       $(basename "$PLAN_PATH")"
  echo "  Plan ID:    $PLAN_ID"
  echo "  Tool:       $tool"
  if [[ -n "$model" ]]; then
  echo "  Model:      $model"
  fi
  echo "  Base:       $BASE_BRANCH"
  echo "  Feature:    $mega_feature_branch"
  echo "  Start:      Phase $start_phase"
  echo "  Max Iters:  $max_iterations per phase"
  if [[ "${WITH_REVIEW:-false}" == "true" ]]; then
  echo "  Review:     enabled"
  fi
  echo "  State:      $STATE_DIR"
  echo "================================================================"
  echo ""

  # Parse the master plan
  echo "Parsing master plan: $PLAN_PATH"
  local phases_json
  phases_json=$(parse_phases "$PLAN_PATH")
  local total_phases
  total_phases=$(echo "$phases_json" | jq 'length')

  if [[ "$total_phases" -eq 0 ]]; then
    echo "Error: No phases found in $PLAN_PATH"
    echo "Ensure phases are formatted as: ## Phase N: Title"
    return 1
  fi

  echo "Found $total_phases phases"
  echo ""

  START_PHASE="$start_phase"
  init_progress "$total_phases"

  # Store base branch and feature branch in masterplan.json
  jq --arg base "$BASE_BRANCH" --arg feat "$mega_feature_branch" \
    '. + {baseBranch: $base, featureBranch: $feat}' \
    "$MEGA_PROGRESS" > "$MEGA_PROGRESS.tmp" && mv "$MEGA_PROGRESS.tmp" "$MEGA_PROGRESS"

  # Phase review template
  local PHASE_REVIEW_PROMPT_TEMPLATE="$SCRIPT_DIR/phase-review-prompt.md"
  local REVIEW_FIXES_PROMPT_TEMPLATE="$SCRIPT_DIR/review-fixes-prompt.md"

  # Phase loop
  for (( phase_idx=0; phase_idx < total_phases; phase_idx++ )); do
    local phase_num phase_title phase_desc
    phase_num=$(echo "$phases_json" | jq -r ".[$phase_idx].phase")
    phase_title=$(echo "$phases_json" | jq -r ".[$phase_idx].title")
    phase_desc=$(echo "$phases_json" | jq -r ".[$phase_idx].description")

    if [[ "$phase_num" -lt "$start_phase" ]]; then
      echo "Skipping Phase $phase_num: $phase_title (before start phase $start_phase)"
      continue
    fi

    local phase_status
    phase_status=$(jq -r --argjson p "$phase_num" \
      '(.phases[] | select(.phase == $p) | .status) // "pending"' \
      "$MEGA_PROGRESS" 2>/dev/null || echo "pending")

    if [[ "$phase_status" == "completed" ]]; then
      echo "Skipping Phase $phase_num: $phase_title (already completed)"
      continue
    fi

    echo ""
    echo "================================================================"
    echo "  Phase $phase_num of $total_phases: $phase_title"
    echo "================================================================"
    echo ""

    local branch_name previous_summary
    branch_name=$(make_branch_name "$phase_num" "$phase_title")
    previous_summary=$(get_previous_phases_summary "$phase_num")

    # Create phase branch from mega feature branch
    git_ensure_branch "$branch_name" "$mega_feature_branch"

    update_progress_start "$phase_num" "$phase_title" "$branch_name"

    # Step 1: Generate PRD
    local prd_path
    prd_path=$(generate_phase_prd "$phase_num" "$phase_title" "$phase_desc" "$previous_summary" "$project_name" "$claude_model_args")
    if [[ $? -ne 0 || -z "$prd_path" ]]; then
      echo "Error: Failed to generate PRD for Phase $phase_num"
      update_progress_failed "$phase_num" 0
      return 1
    fi

    # Step 2: Convert PRD to prd.json
    convert_prd_to_json "$prd_path" "$phase_num" "$phase_title" "$project_name" "$claude_model_args" "$branch_name"
    if [[ $? -ne 0 ]]; then
      echo "Error: Failed to convert PRD for Phase $phase_num"
      update_progress_failed "$phase_num" 0
      return 1
    fi

    # Step 3: Run ralph for this phase (as a function call, not subprocess)
    echo ""
    echo "  Running Ralph for Phase $phase_num ..."
    echo ""

    local ralph_exit=0
    run_ralph "$max_iterations" "$tool" "$model" || ralph_exit=$?

    # Exit immediately on SIGINT/SIGTERM
    if [[ $ralph_exit -eq 130 || $ralph_exit -eq 143 ]]; then
      echo ""
      echo "Interrupted."
      exit $ralph_exit
    fi

    # Determine results
    local stories_total stories_done
    stories_total=$(jq '.userStories | length' "$STATE_DIR/prd.json" 2>/dev/null || echo "0")
    stories_done=$(jq '[.userStories[] | select(.passes == true)] | length' "$STATE_DIR/prd.json" 2>/dev/null || echo "0")

    if [[ "$ralph_exit" -eq 0 ]]; then
      echo ""
      echo "  Phase $phase_num completed! ($stories_done/$stories_total stories done)"

      update_progress_complete "$phase_num" "$stories_done"

      # Phase review (if enabled)
      if [[ "${WITH_REVIEW:-false}" == "true" && -f "$PHASE_REVIEW_PROMPT_TEMPLATE" ]]; then
        local padded_phase_num
        padded_phase_num=$(printf '%02d' "$phase_num")
        local phase_review_doc="$STATE_DIR/reviews/review-phase-${phase_num}.md"

        echo ""
        echo "  ── Phase $phase_num review ──"

        run_review_turn "$PHASE_REVIEW_PROMPT_TEMPLATE" \
          "{{PHASE_NUMBER}}" "$phase_num" \
          "{{PHASE_TITLE}}" "$phase_title" \
          "{{PARENT_BRANCH}}" "$mega_feature_branch" \
          "{{PHASE_BRANCH}}" "$branch_name" \
          "{{PHASE_NUMBER_PADDED}}" "$padded_phase_num" \
          "{{REVIEW_DOC_PATH}}" "$phase_review_doc"

        # Phase fixes
        if [[ -f "$phase_review_doc" ]] && grep -q "NEEDS-FIXES" "$phase_review_doc" 2>/dev/null; then
          echo "  Phase review verdict: NEEDS-FIXES — running fixes..."
          run_review_turn "$REVIEW_FIXES_PROMPT_TEMPLATE" \
            "{{STORY_ID}}" "Phase-$phase_num" \
            "{{REVIEW_DOC_PATH}}" "$phase_review_doc"
        elif [[ -f "$phase_review_doc" ]]; then
          echo "  Phase review verdict: PASS"
        fi

        echo "  ── Phase review complete ──"
        echo ""
      fi

      # Merge phase branch back to mega feature branch
      git_merge_branch "$branch_name" "$mega_feature_branch"

      # Reflect on learnings
      reflect_and_update_plan "$phase_num" "$phase_title" "$project_name" "$claude_model_args"

      # Archive
      archive_phase "$phase_num" "$phase_title" "$branch_name"
    else
      echo ""
      echo "  Phase $phase_num did not complete ($stories_done/$stories_total stories done)"
      echo "  Ralph exited with code $ralph_exit"

      update_progress_failed "$phase_num" "$stories_done"

      echo ""
      echo "To resume, run:"
      local resume_cmd=".ralph/run.sh --plan $PLAN_ID --start-phase $phase_num --tool $tool"
      if [[ -n "$model" ]]; then
        resume_cmd="$resume_cmd --model $model"
      fi
      echo "  $resume_cmd"
      return 1
    fi
  done

  # All phases complete
  echo ""
  echo "================================================================"
  echo "  MEGA-RALPH COMPLETE"
  echo "================================================================"
  local completed_count
  completed_count=$(jq '[.phases[] | select(.status == "completed")] | length' "$MEGA_PROGRESS")
  echo "  All $completed_count phases completed successfully!"
  echo "  Feature branch: $mega_feature_branch"
  echo "  Merge to $BASE_BRANCH when ready (e.g., via PR)"
  echo "  Progress: $MEGA_PROGRESS"
  echo "================================================================"
}

# ═══════════════════════════════════════════════════════════════════════════
# ARGUMENT PARSING & DISPATCH
# ═══════════════════════════════════════════════════════════════════════════

# Check for subcommands first
case "${1:-}" in
  status)
    do_status
    ;;
  switch)
    do_switch
    ;;
  -h|--help)
    show_help
    ;;
esac

# ---------------------------------------------------------------------------
# Load config.sh defaults (if present)
# ---------------------------------------------------------------------------
# Config values are overridden by CLI arguments.
# Example .ralph/config.sh:
#   export RALPH_TOOL=claude
#   export RALPH_MODEL=sonnet
#   export RALPH_BASE=main
#   export RALPH_WITH_REVIEW=true
#   export RALPH_REVIEW_TOOL=claude
#   export RALPH_REVIEW_MODEL=opus
#   export RALPH_MAX_ITERATIONS=15
#   export RALPH_MAX_ITERATIONS_PER_PHASE=25
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/config.sh"
fi

# Parse arguments (CLI overrides config.sh)
TOOL="${RALPH_TOOL:-claude}"
MODEL="${RALPH_MODEL:-}"
MAX_ITERATIONS="${RALPH_MAX_ITERATIONS:-}"
PLAN=""
START_PHASE=1
MAX_ITERATIONS_PER_PHASE="${RALPH_MAX_ITERATIONS_PER_PHASE:-25}"
ARG_BASE_BRANCH="${RALPH_BASE:-}"
WITH_REVIEW="${RALPH_WITH_REVIEW:-false}"
REVIEW_TOOL="${RALPH_REVIEW_TOOL:-}"
REVIEW_MODEL="${RALPH_REVIEW_MODEL:-}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --model=*)
      MODEL="${1#*=}"
      shift
      ;;
    --plan)
      PLAN="$2"
      shift 2
      ;;
    --plan=*)
      PLAN="${1#*=}"
      shift
      ;;
    --start-phase)
      START_PHASE="$2"
      shift 2
      ;;
    --start-phase=*)
      START_PHASE="${1#*=}"
      shift
      ;;
    --max-iterations-per-phase)
      MAX_ITERATIONS_PER_PHASE="$2"
      shift 2
      ;;
    --max-iterations-per-phase=*)
      MAX_ITERATIONS_PER_PHASE="${1#*=}"
      shift
      ;;
    --base)
      ARG_BASE_BRANCH="$2"
      shift 2
      ;;
    --base=*)
      ARG_BASE_BRANCH="${1#*=}"
      shift
      ;;
    --with-review)
      WITH_REVIEW="true"
      shift
      ;;
    --review-tool)
      REVIEW_TOOL="$2"
      shift 2
      ;;
    --review-tool=*)
      REVIEW_TOOL="${1#*=}"
      shift
      ;;
    --review-model)
      REVIEW_MODEL="$2"
      shift 2
      ;;
    --review-model=*)
      REVIEW_MODEL="${1#*=}"
      shift
      ;;
    -h|--help)
      show_help
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" && "$TOOL" != "codex" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp', 'claude', or 'codex'."
  exit 1
fi

# ---------------------------------------------------------------------------
# Mode detection & dispatch
# ---------------------------------------------------------------------------

# If --plan is given, always run mega mode
if [[ -n "$PLAN" ]]; then
  run_mega "$PLAN" "$START_PHASE" "$MAX_ITERATIONS_PER_PHASE" "$TOOL" "$MODEL"
  exit $?
fi

# Auto-detect mode from current symlink state
if [[ -L "$SCRIPT_DIR/current" ]]; then
  if [[ -f "$STATE_DIR/masterplan.json" ]]; then
    # Mega mode — resume
    run_mega "" "$START_PHASE" "$MAX_ITERATIONS_PER_PHASE" "$TOOL" "$MODEL"
    exit $?
  elif [[ -f "$STATE_DIR/prd.json" ]]; then
    # Ralph mode
    if [[ -z "$MAX_ITERATIONS" ]]; then
      MAX_ITERATIONS=10
    fi
    run_ralph "$MAX_ITERATIONS" "$TOOL" "$MODEL"
    exit $?
  fi
fi

# Check if there are masterplan files in plans/
if ls "$PLANS_DIR/"*-M*-*.md 2>/dev/null | grep -qv '\-P[0-9]'; then
  run_mega "" "$START_PHASE" "$MAX_ITERATIONS_PER_PHASE" "$TOOL" "$MODEL"
  exit $?
fi

echo "Error: No active plan found."
echo ""
echo "To get started:"
echo "  1. Create a PRD:        use /prd skill"
echo "     Convert to JSON:     use /ralph skill"
echo "     Run:                 .ralph/run.sh --tool claude"
echo ""
echo "  2. Create a masterplan: use /masterplan skill"
echo "     Run:                 .ralph/run.sh --plan M1 --tool claude"
exit 1
