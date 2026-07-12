#!/usr/bin/env bash
set -euo pipefail

# check-session.sh - turns the workflow's "the agent must..." wishes into an
# actual check. Intended uses:
#   - run manually before wrapping up a task
#   - wire as a git pre-commit hook (use --strict to block commits on failure)
#
# Checks:
#   1. The explicit/current session exists and its status.md has a valid status.
#   2. project-commands.sh defines cmd_validate for real (not just _undefined).
#   3. module.md docs whose verified-against: marker has fallen far behind HEAD
#      (drift), or is unset.
#
# Session selection: --session, then AGENT_SESSION_ID, then the sole ACTIVE
# session. When none is ACTIVE, the most recently modified session is checked
# as a compatibility fallback; multiple ACTIVE sessions require an explicit ID.
#
# Exit: non-zero on hard failures ONLY in --strict mode; otherwise 0 with warnings.

STRICT=0
SESSION_ID="${AGENT_SESSION_ID:-}"

usage() {
  echo "Usage: $0 [--strict] [--session <session-directory-name>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1; shift ;;
    --session)
      [[ $# -ge 2 ]] || { echo "ERROR: --session requires a value" >&2; usage; exit 2; }
      SESSION_ID="$2"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INSTR="$ROOT_DIR/instructions"
STALE_THRESHOLD="${CHECK_SESSION_STALE_COMMITS:-50}"

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"

fail=0
warn() { echo "WARN: $*" >&2; }
err()  { echo "FAIL: $*" >&2; fail=1; }

# 1. Select the current session explicitly, by the sole ACTIVE status, or as a
# compatibility fallback by modification time when no session is ACTIVE.
session_root="$INSTR/session-logs"
selected=""

if [[ -n "$SESSION_ID" ]]; then
  if validate_helper_name "$SESSION_ID" "session name"; then
    selected="$session_root/$SESSION_ID"
    if [[ ! -d "$selected" || -L "$selected" ]]; then
      err "selected session does not exist as a real directory: $SESSION_ID"
      selected=""
    fi
  else
    err "invalid session name: $SESSION_ID"
  fi
else
  active_sessions=()
  while IFS= read -r -d '' candidate; do
    status_file="$candidate/status.md"
    if [[ -f "$status_file" && ! -L "$status_file" ]] &&
       grep -qE '^Status:[[:space:]]*ACTIVE[[:space:]]*$' "$status_file"; then
      active_sessions+=("$candidate")
    fi
  done < <(find "$session_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)

  if [[ "${#active_sessions[@]}" -eq 1 ]]; then
    selected="${active_sessions[0]}"
  elif [[ "${#active_sessions[@]}" -gt 1 ]]; then
    err "multiple ACTIVE sessions found; pass --session <name> or set AGENT_SESSION_ID"
    for candidate in "${active_sessions[@]}"; do
      warn "active session: $(basename "$candidate")"
    done
  else
    newest_mtime=-1
    while IFS= read -r -d '' candidate; do
      candidate_mtime="$(stat -c %Y "$candidate" 2>/dev/null || echo 0)"
      if [[ "$candidate_mtime" -gt "$newest_mtime" ]]; then
        newest_mtime="$candidate_mtime"
        selected="$candidate"
      fi
    done < <(find "$session_root" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
    if [[ -n "$selected" ]]; then
      warn "no ACTIVE session found; checking most recently modified session: $(basename "$selected")"
    fi
  fi
fi

if [[ -z "$selected" && "$fail" -eq 0 ]]; then
  err "no session log under instructions/session-logs/ (helpers/create-session-log.sh <slug>)"
elif [[ -n "$selected" ]]; then
  if [[ -L "$selected/status.md" ]]; then
    err "session log $(basename "$selected") has a symlinked status.md"
  elif [[ ! -f "$selected/status.md" ]]; then
    err "session log $(basename "$selected") has no status.md"
  elif ! grep -qE '^Status:[[:space:]]*(ACTIVE|PAUSED|FAILED|COMPLETE)[[:space:]]*$' "$selected/status.md"; then
    err "status.md in $(basename "$selected") has no valid Status: line"
  else
    echo "check-session: session $(basename "$selected")"
  fi
fi

# 2. validate gate is defined for real.
cmds="$INSTR/project-commands.sh"
if [[ ! -f "$cmds" ]]; then
  err "instructions/project-commands.sh missing — run project-init"
elif grep -qE '^cmd_validate\(\)[[:space:]]*\{[[:space:]]*_undefined' "$cmds"; then
  err "cmd_validate is still _undefined in project-commands.sh — validate gate is not real yet"
fi

# 3. Doc staleness (best-effort; needs git).
if command -v git >/dev/null 2>&1 && git -C "$ROOT_DIR" rev-parse >/dev/null 2>&1; then
  head_short="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)"
  while IFS= read -r f; do
    marker_line="$(grep -m1 'verified-against:' "$f" || true)"
    commit="$(printf '%s' "$marker_line" | sed -E 's/.*verified-against:[[:space:]]*//; s/[[:space:]].*//; s/<.*>//')"
    rel="${f#"$ROOT_DIR"/}"
    if [[ -z "$commit" ]]; then
      warn "$rel: verified-against marker is unset"
      continue
    fi
    if ! git -C "$ROOT_DIR" cat-file -e "${commit}^{commit}" 2>/dev/null; then
      warn "$rel: verified-against '$commit' is not a known commit"
      continue
    fi
    if git -C "$ROOT_DIR" merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
      behind="$(git -C "$ROOT_DIR" rev-list --count "${commit}..HEAD" 2>/dev/null || echo 0)"
      if [[ "$behind" -gt "$STALE_THRESHOLD" ]]; then
        warn "$rel: verified-against $commit is $behind commits behind HEAD ($head_short) — likely stale"
      fi
    fi
  done < <(grep -rIl 'verified-against:' "$INSTR/modules" 2>/dev/null || true)
else
  warn "git not available; skipping doc-staleness check"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "check-session: FAILED" >&2
  if [[ "$STRICT" -eq 1 ]]; then exit 1; fi
  echo "(non-strict: reporting only, not blocking)" >&2
  exit 0
fi
echo "check-session: ok"
