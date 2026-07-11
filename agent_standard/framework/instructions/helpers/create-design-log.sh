#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <design-slug>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TARGET="$ROOT_DIR/instructions/design-logs/$(date +%F)-$1.md"

if [[ -f "$TARGET" ]]; then
  echo "Skipping existing file: $TARGET"
  exit 0
fi

cp "$ROOT_DIR/instructions/design-template.md" "$TARGET"
echo "Wrote: $TARGET"
