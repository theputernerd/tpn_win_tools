#!/usr/bin/env bash
set -euo pipefail

# Run this script from the directory where the links should be created, such
# as ~/.local/bin:
#   /path/to/tpn_win_tools/create_symlinks.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd -P)"
LINK_DIR="$(pwd -P)"

TARGETS=(
  "$SCRIPT_DIR/agent_standard/bootstrap_agent_standard_v4.sh"
  "$SCRIPT_DIR/codex_scripts/codex_kez.sh"
  "$SCRIPT_DIR/codex_scripts/codex_pers.sh"
  "$SCRIPT_DIR/codex_scripts/codex_tpn.sh"
)

# Check every target and destination before changing anything.
for target in "${TARGETS[@]}"; do
  link="$LINK_DIR/$(basename -- "$target")"

  if [[ ! -f "$target" ]]; then
    echo "ERROR: script not found: $target" >&2
    exit 1
  fi

  if [[ -L "$link" && "$(readlink -f -- "$link")" == "$(readlink -f -- "$target")" ]]; then
    continue
  fi

  if [[ -e "$link" || -L "$link" ]]; then
    echo "ERROR: $link already exists and is not a symlink to $target" >&2
    exit 1
  fi
done

for target in "${TARGETS[@]}"; do
  link="$LINK_DIR/$(basename -- "$target")"

  if [[ -L "$link" ]]; then
    echo "already linked: $link -> $target"
    continue
  fi

  ln -s -- "$target" "$link"
  echo "linked: $link -> $target"
done
