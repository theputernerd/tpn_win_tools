#!/usr/bin/env bash
set -euo pipefail

# tasks.sh - framework-managed command dispatcher.
#
# This file is the STABLE interface every task and the agent-contract rely on:
#   ./tasks.sh setup | build | test | lint | run | validate
#
# It is intentionally tech-agnostic. The actual commands live in
# instructions/project-commands.sh (user content), which the project-init task
# fills in once the stack is known. Do not put project-specific commands here.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMANDS_FILE="$ROOT_DIR/instructions/project-commands.sh"
VERBS="setup build test lint run validate"

usage() {
  echo "Usage: ./tasks.sh {${VERBS// /|}} [args...]"
  echo "  validate is the completion gate a task must pass before it is 'done'."
}

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
verb="$1"; shift || true

case " $VERBS " in
  *" $verb "*) ;;
  *) echo "Unknown verb: $verb" >&2; usage >&2; exit 2 ;;
esac

if [[ ! -f "$COMMANDS_FILE" ]]; then
  echo "ERROR: $COMMANDS_FILE is missing." >&2
  echo "Run the project-init task to create and fill it." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$COMMANDS_FILE"

fn="cmd_${verb}"
if ! declare -F "$fn" >/dev/null; then
  echo "ERROR: '$verb' is not defined in instructions/project-commands.sh." >&2
  echo "Define ${fn}() there (project-init task)." >&2
  exit 1
fi

"$fn" "$@"
