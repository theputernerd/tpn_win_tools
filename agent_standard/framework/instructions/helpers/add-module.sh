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

mkdir -p "$MODULE_DIR"

emit() {  # src dst
  local src="$1" dst="$2"
  if [[ -f "$dst" ]]; then
    echo "Skipping existing file: $dst"; return 0
  fi
  sed "s/<name>/$NAME/g" "$src" > "$dst"
  echo "Wrote: $dst"
}

emit "$TEMPLATES_DIR/module.md"           "$MODULE_DIR/module.md"
emit "$TEMPLATES_DIR/module-changelog.md" "$MODULE_DIR/changelog.md"

echo "Remember to set the verified-against: marker in module.md to the current commit."
