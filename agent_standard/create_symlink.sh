#!/usr/bin/env bash
set -euo pipefail

# create_symlink.sh
#
# Run this from wherever you want the symlink dropped (e.g. ~), invoking it
# by its full path:
#   /path/to/agent_standard/create_symlink.sh
#
# Creates ./bootstrap_agent_standard_v4.sh in the current directory as a
# symlink to the real bootstrap script next to this one, so you can then run
# ~/bootstrap_agent_standard_v4.sh from any project root.

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TARGET="$SCRIPT_DIR/bootstrap_agent_standard_v4.sh"
LINK_NAME="$(pwd)/bootstrap_agent_standard_v4.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: bootstrap script not found next to this script: $TARGET" >&2
  exit 1
fi

if [[ -L "$LINK_NAME" && "$(readlink -f "$LINK_NAME")" == "$(readlink -f "$TARGET")" ]]; then
  echo "already linked: $LINK_NAME -> $TARGET"
  exit 0
fi

if [[ -e "$LINK_NAME" || -L "$LINK_NAME" ]]; then
  echo "ERROR: $LINK_NAME already exists and is not a symlink to $TARGET" >&2
  exit 1
fi

ln -s "$TARGET" "$LINK_NAME"
echo "linked: $LINK_NAME -> $TARGET"
