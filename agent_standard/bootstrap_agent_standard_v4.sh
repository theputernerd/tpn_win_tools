#!/usr/bin/env bash
set -euo pipefail

# bootstrap_agent_standard_v4.sh
#
# Initializes the generic agent-instructions framework in the current project.
# This is deliberately a fresh initializer, not an upgrader or merge tool.

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR/framework"

ASSUME_YES=0
DRY_RUN=0
CLAUDE_MODE="symlink"   # symlink | copy

# These files are templates for project-owned content. The distinction is
# informational during a fresh install; no installed files are upgraded later.
USER_SEED_FILES=(
  "instructions/project-commands.sh"
  "instructions/product/overview.md"
  "instructions/product/roadmap.md"
)

usage() {
  cat <<'EOH'
Usage: ./bootstrap_agent_standard_v4.sh [--dry-run] [--yes] [--copy-claude]

Initializes the Agent Standard framework in the current directory.

This tool is for a project that does not already contain Agent Standard. It
does not merge with or upgrade an existing installation. If a reserved path
already exists, the initializer stops without changing anything.

Options:
  --dry-run      Preview every addition without changing the filesystem.
  --yes          Confirm initialization non-interactively.
  --copy-claude  Create CLAUDE.md as a copy instead of a symlink to AGENTS.md.
  -h, --help     Show this help.

After initialization, all installed files belong to the project. Future
versions of this initializer will not overwrite them automatically.
EOH
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --copy-claude) CLAUDE_MODE="copy"; shift ;;
    --upgrade|--force)
      echo "ERROR: $1 is no longer supported." >&2
      echo "This tool only initializes projects without an existing Agent Standard installation." >&2
      echo "No files were changed." >&2
      exit 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -d "$FRAMEWORK_DIR" ]]; then
  echo "ERROR: framework directory not found next to this script: $FRAMEWORK_DIR" >&2
  exit 1
fi

PROJECT_ROOT="$(pwd -P)"

if [[ "$PROJECT_ROOT" == "$SCRIPT_DIR" ]]; then
  echo "ERROR: refusing to initialize the framework's own source directory." >&2
  echo "Change to the project root first, then run this script by absolute path." >&2
  exit 1
fi

is_user_seed() {
  local rel="$1"
  local seed
  for seed in "${USER_SEED_FILES[@]}"; do
    [[ "$rel" == "$seed" ]] && return 0
  done
  return 1
}

reject_unsafe_relative_path() {
  local rel="$1"
  local part
  local -a parts
  [[ -n "$rel" && "$rel" != /* ]] || return 1
  IFS='/' read -r -a parts <<< "$rel"
  for part in "${parts[@]}"; do
    [[ -n "$part" && "$part" != "." && "$part" != ".." ]] || return 1
  done
}

symlink_in_target_path() {
  local rel="$1"
  local current="$PROJECT_ROOT"
  local part
  local -a parts
  IFS='/' read -r -a parts <<< "$rel"
  for part in "${parts[@]}"; do
    current="$current/$part"
    if [[ -L "$current" ]]; then
      printf '%s' "$current"
      return 0
    fi
  done
  return 1
}

mapfile -d '' -t framework_files < <(find "$FRAMEWORK_DIR" -type f -print0 | sort -z)
if [[ "${#framework_files[@]}" -eq 0 ]]; then
  echo "ERROR: framework contains no files: $FRAMEWORK_DIR" >&2
  exit 1
fi

echo "Agent Standard initialization"
echo ""
echo "Target: $PROJECT_ROOT"
echo ""
echo "This initializer does not merge with or upgrade an existing Agent Standard installation."
echo "Existing application files outside the reserved paths will not be modified."
echo ""

conflicts=0
unsafe=0

# These roots are reserved as a unit. Refusing an existing directory avoids a
# partial/mixed installation even if none of today's individual files collide.
reserved_roots=(".framework-version" "AGENTS.md" "tasks.sh" "instructions" "CLAUDE.md")
for rel in "${reserved_roots[@]}"; do
  if unsafe_path="$(symlink_in_target_path "$rel")"; then
    echo "UNSAFE    $rel (symlink at $unsafe_path)"
    unsafe=$((unsafe + 1))
  elif [[ -e "$PROJECT_ROOT/$rel" ]]; then
    echo "CONFLICT  $rel (reserved path already exists)"
    conflicts=$((conflicts + 1))
  fi
done

if [[ "$conflicts" -ne 0 || "$unsafe" -ne 0 ]]; then
  echo ""
  echo "ERROR: initialization cannot continue safely." >&2
  echo "Resolve the paths above manually; this initializer will not overwrite, merge, or follow them." >&2
  echo "No files were changed." >&2
  exit 1
fi

echo "Planned additions:"
for src in "${framework_files[@]}"; do
  rel="${src#"$FRAMEWORK_DIR"/}"
  if ! reject_unsafe_relative_path "$rel"; then
    echo "ERROR: unsafe path in framework source: $rel" >&2
    exit 1
  fi
  if is_user_seed "$rel"; then
    printf '  SEED    %s\n' "$rel"
  else
    printf '  CREATE  %s\n' "$rel"
  fi
done
if [[ "$CLAUDE_MODE" == "copy" ]]; then
  echo "  COPY    CLAUDE.md from AGENTS.md"
else
  echo "  LINK    CLAUDE.md -> AGENTS.md"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "Dry run complete. No files were changed."
  exit 0
fi

if [[ "$ASSUME_YES" -ne 1 ]]; then
  if [[ ! -t 0 ]]; then
    echo "" >&2
    echo "ERROR: confirmation is required, but input is not interactive." >&2
    echo "Review with --dry-run, then pass --yes to initialize non-interactively." >&2
    echo "No files were changed." >&2
    exit 1
  fi
  echo ""
  read -r -p "Continue? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES|Yes) ;;
    *) echo "Cancelled. No files were changed."; exit 0 ;;
  esac
fi

copied=0
seeded=0
for src in "${framework_files[@]}"; do
  rel="${src#"$FRAMEWORK_DIR"/}"
  dst="$PROJECT_ROOT/$rel"
  mkdir -p "$(dirname "$dst")"
  cp -p -- "$src" "$dst"
  if is_user_seed "$rel"; then
    echo "seed          $rel"
    seeded=$((seeded + 1))
  else
    echo "write         $rel"
    copied=$((copied + 1))
  fi
done

claude_path="$PROJECT_ROOT/CLAUDE.md"
agents_path="$PROJECT_ROOT/AGENTS.md"
if [[ "$CLAUDE_MODE" == "copy" ]]; then
  cp -p -- "$agents_path" "$claude_path"
  echo "write         CLAUDE.md (copy)"
else
  if ln -s "AGENTS.md" "$claude_path" 2>/dev/null; then
    echo "link          CLAUDE.md -> AGENTS.md"
  else
    cp -p -- "$agents_path" "$claude_path"
    echo "write         CLAUDE.md (symlink unavailable; copied instead)"
  fi
fi

version="$(cat "$FRAMEWORK_DIR/.framework-version" 2>/dev/null || echo unknown)"
echo ""
echo "Framework v$version initialized in: $PROJECT_ROOT"
echo "  created: $copied   seeded: $seeded"
echo ""
echo "Next steps:"
echo "  1) Review AGENTS.md and any existing project-specific agent instructions."
echo "  2) Run the first task 'project-init': choose the stack and fill"
echo "     instructions/project-commands.sh so ./tasks.sh validate works."
echo "  3) Seed instructions/product/overview.md and roadmap.md with intent."
echo "  4) Start a task log: instructions/helpers/create-session-log.sh <slug>"
