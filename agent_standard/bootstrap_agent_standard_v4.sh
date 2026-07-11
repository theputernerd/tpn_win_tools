#!/usr/bin/env bash
set -euo pipefail

# bootstrap_agent_standard_v4.sh
#
# Installs (or upgrades) the generic agent-instructions framework into the
# current project root. Unlike v3, the framework content lives as real files
# under ./framework/ next to this script, so it can be edited normally and
# versioned/upgraded in existing projects without clobbering user content.

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
FRAMEWORK_DIR="$SCRIPT_DIR/framework"

MODE="install"          # install | upgrade
FORCE=0
CLAUDE_MODE="symlink"   # symlink | copy

# Files that belong to the user once written. They are seeded only if missing
# and are NEVER overwritten, even by --upgrade or --force.
USER_SEED_FILES=(
  "instructions/project-commands.sh"
  "instructions/product/overview.md"
  "instructions/product/roadmap.md"
)

usage() {
  cat <<'EOH'
Usage: ./bootstrap_agent_standard_v4.sh [--upgrade] [--force] [--copy-claude]

Installs the agent-instructions framework into the current directory.

Modes:
  (default)      Fresh install. Creates every missing file; leaves existing
                 files untouched.
  --upgrade      Overwrite framework-managed files with the versions shipped in
                 ./framework/. User content (see below) is never touched. Use
                 this to pull framework improvements into an existing project.

Options:
  --force        Overwrite managed files during a fresh install too.
  --copy-claude  Create CLAUDE.md as a real copy instead of a symlink to AGENTS.md.
  -h, --help     Show this help.

User content (seeded if missing, never overwritten):
  instructions/project-commands.sh, instructions/product/overview.md,
  instructions/product/roadmap.md, and everything you create under
  instructions/session-logs/, instructions/design-logs/,
  instructions/product/modules/, instructions/modules/, and
  instructions/project-conventions/.
EOH
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --upgrade) MODE="upgrade"; shift ;;
    --force) FORCE=1; shift ;;
    --copy-claude) CLAUDE_MODE="copy"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ! -d "$FRAMEWORK_DIR" ]]; then
  echo "ERROR: framework directory not found next to this script: $FRAMEWORK_DIR" >&2
  exit 1
fi

PROJECT_ROOT="$(pwd)"

if [[ "$(cd "$PROJECT_ROOT" && pwd)" == "$SCRIPT_DIR" ]]; then
  echo "ERROR: refusing to install into the framework's own source directory." >&2
  echo "cd into your project root first, then run this script by absolute path." >&2
  exit 1
fi

is_user_seed() {
  local rel="$1"
  local s
  for s in "${USER_SEED_FILES[@]}"; do
    [[ "$rel" == "$s" ]] && return 0
  done
  return 1
}

copied=0 skipped=0 upgraded=0 seeded=0

# Walk every file shipped in the framework and place it appropriately.
while IFS= read -r -d '' src; do
  rel="${src#"$FRAMEWORK_DIR"/}"
  dst="$PROJECT_ROOT/$rel"
  mkdir -p "$(dirname "$dst")"

  if is_user_seed "$rel"; then
    if [[ -e "$dst" ]]; then
      echo "keep (user)   $rel"; skipped=$((skipped+1))
    else
      cp -p "$src" "$dst"; echo "seed          $rel"; seeded=$((seeded+1))
    fi
    continue
  fi

  # Managed file.
  if [[ ! -e "$dst" ]]; then
    cp -p "$src" "$dst"; echo "write         $rel"; copied=$((copied+1))
  elif [[ "$MODE" == "upgrade" || "$FORCE" -eq 1 ]]; then
    cp -p "$src" "$dst"; echo "upgrade       $rel"; upgraded=$((upgraded+1))
  else
    echo "skip (exists) $rel"; skipped=$((skipped+1))
  fi
done < <(find "$FRAMEWORK_DIR" -type f -print0)

# CLAUDE.md -> AGENTS.md
claude_path="$PROJECT_ROOT/CLAUDE.md"
agents_path="$PROJECT_ROOT/AGENTS.md"
if [[ "$CLAUDE_MODE" == "copy" ]]; then
  if [[ -e "$claude_path" && "$MODE" != "upgrade" && "$FORCE" -ne 1 ]]; then
    echo "skip (exists) CLAUDE.md"
  else
    [[ -e "$claude_path" || -L "$claude_path" ]] && rm -f "$claude_path"
    cp -p "$agents_path" "$claude_path"; echo "write         CLAUDE.md (copy)"
  fi
else
  if [[ -L "$claude_path" ]]; then
    echo "keep          CLAUDE.md (symlink)"
  elif [[ -e "$claude_path" ]]; then
    echo "skip (exists) CLAUDE.md (not a symlink; leaving as-is)"
  else
    if ln -s "AGENTS.md" "$claude_path" 2>/dev/null; then
      echo "link          CLAUDE.md -> AGENTS.md"
    else
      cp -p "$agents_path" "$claude_path"; echo "write         CLAUDE.md (symlink failed; copied)"
    fi
  fi
fi

version="$(cat "$FRAMEWORK_DIR/.framework-version" 2>/dev/null || echo unknown)"
echo ""
echo "Framework v$version installed into: $PROJECT_ROOT"
echo "  new: $copied   upgraded: $upgraded   seeded: $seeded   skipped: $skipped"
echo ""
if [[ "$MODE" == "upgrade" ]]; then
  echo "Upgrade complete. Managed files refreshed; user content left intact."
else
  echo "Next steps:"
  echo "  1) Run the FIRST task 'project-init': choose the stack and fill"
  echo "     instructions/project-commands.sh so ./tasks.sh validate works."
  echo "  2) Seed instructions/product/overview.md and roadmap.md with intent."
  echo "  3) Start a task log: instructions/helpers/create-session-log.sh <slug>"
  echo "  4) Add a module doc when you build one: instructions/helpers/add-module.sh <name>"
fi
