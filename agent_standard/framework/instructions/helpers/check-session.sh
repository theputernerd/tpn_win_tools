#!/usr/bin/env bash
set -euo pipefail

# check-session.sh - turns the workflow's "the agent must..." wishes into an
# actual check. Intended uses:
#   - run manually before wrapping up a task
#   - wire as a git pre-commit hook (use --strict to block commits on failure)
#
# Checks:
#   1. A session log exists and its status.md has a valid Status: line.
#   2. project-commands.sh defines cmd_validate for real (not just _undefined).
#   3. module.md docs whose verified-against: marker has fallen far behind HEAD
#      (drift), or is unset.
#
# Exit: non-zero on hard failures ONLY in --strict mode; otherwise 0 with warnings.

STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INSTR="$ROOT_DIR/instructions"
STALE_THRESHOLD="${CHECK_SESSION_STALE_COMMITS:-50}"

fail=0
warn() { echo "WARN: $*" >&2; }
err()  { echo "FAIL: $*" >&2; fail=1; }

# 1. Session log present and valid.
latest="$(find "$INSTR/session-logs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n1)"
if [[ -z "$latest" ]]; then
  err "no session log under instructions/session-logs/ (helpers/create-session-log.sh <slug>)"
elif [[ ! -f "$latest/status.md" ]]; then
  err "session log $(basename "$latest") has no status.md"
elif ! grep -qE '^Status:[[:space:]]*(ACTIVE|PAUSED|FAILED|COMPLETE)\b' "$latest/status.md"; then
  err "status.md in $(basename "$latest") has no valid Status: line"
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
