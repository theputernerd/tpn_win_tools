#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <task-slug> [tier]   # tier: trivial|standard|high-risk (default standard)" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SLUG="$1"
TIER="${2:-standard}"
DIR="$ROOT_DIR/instructions/session-logs/$(date +%F)-$SLUG"

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"
validate_helper_name "$SLUG" "task slug"
validate_task_tier "$TIER"
reject_symlinks_under_root "$ROOT_DIR" "$DIR"
require_directory_or_missing "$DIR"

if [[ -e "$DIR" ]]; then
  echo "ERROR: session log already exists: $DIR" >&2
  echo "Choose a different slug or continue the existing session explicitly." >&2
  exit 1
fi

mkdir -p "$DIR"

BRANCH="$(git -C "$ROOT_DIR" branch --show-current 2>/dev/null || true)"
HEAD_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
STATUS_SHORT="$(git -C "$ROOT_DIR" status --short 2>/dev/null || true)"
[[ -z "$STATUS_SHORT" ]] && STATUS_SHORT="clean or not a git repo"
NOW="$(date -Iseconds)"

write_if_missing() { # path  (content on stdin)
  local path="$1"
  if [[ -f "$path" ]]; then echo "Skipping existing file: $path"; cat >/dev/null; return 0; fi
  cat > "$path"; echo "Wrote: $path"
}

write_if_missing "$DIR/status.md" <<EOF
# Session Status

Task: $SLUG
Tier: $TIER
Status: ACTIVE
Agent / Model:
Started: $NOW
Last updated: $NOW

## Current phase
- intake

## Git state
- Branch: $BRANCH
- Base commit: $HEAD_COMMIT
- Current HEAD: $HEAD_COMMIT
- Last checkpoint:
- Last known-good:
- Working tree: $STATUS_SHORT

## Current checkpoint
- Last completed step: session log created
- Current next step: escalation check, then plan
- Repo may be in partial state: no
- Expected next log entry: PLAN

## Validation
- Last \`./tasks.sh validate\` result: not run

## Outstanding work / Risks
-

## Restart instructions
- First file to read: instructions/README.md
- Next action: escalation check, write plan
- Cautions:
EOF

write_if_missing "$DIR/action-log.md" <<EOF
# Action Log

## $NOW
Type: STATE
Details:
- Session log created for task: $SLUG (tier: $TIER)
- Branch: $BRANCH  HEAD: $HEAD_COMMIT
- Working tree: $STATUS_SHORT
- No implementation work started yet
EOF

write_if_missing "$DIR/handoff.md" <<EOF
# Handoff

Status: ACTIVE

## Summary
- Session initialised.

## What was finished / What remains
- Done: session log created, git state recorded.
- Remains: escalation check, plan, execute, validate, update docs.

## Validation status
- \`./tasks.sh validate\`: not run

## Git state
- Branch: $BRANCH  Base/HEAD: $HEAD_COMMIT

## Resume notes
- Read status.md, then the latest action-log.md entries.
EOF

echo "Session log ready: $DIR"
