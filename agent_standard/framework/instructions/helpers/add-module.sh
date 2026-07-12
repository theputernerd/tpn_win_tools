#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <module-name>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="$1"
MODULE_DIR="$ROOT_DIR/instructions/modules/$NAME"
TEMPLATES_DIR="$ROOT_DIR/instructions/templates"

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"
validate_helper_name "$NAME" "module name"
reject_symlinks_under_root "$ROOT_DIR" "$MODULE_DIR"
require_directory_or_missing "$MODULE_DIR"

mkdir -p "$MODULE_DIR"

emit() {  # src dst
  local src="$1" dst="$2"
  reject_symlinks_under_root "$ROOT_DIR" "$dst"
  require_regular_or_missing "$dst"
  if [[ -f "$dst" ]]; then
    echo "Skipping existing file: $dst"; return 0
  fi
  sed "s|<name>|$NAME|g" "$src" > "$dst"
  echo "Wrote: $dst"
}

emit "$TEMPLATES_DIR/module.md"           "$MODULE_DIR/module.md"
emit "$TEMPLATES_DIR/module-changelog.md" "$MODULE_DIR/changelog.md"

echo "Remember to set verified-against to the existing implementation commit used as the review baseline."
