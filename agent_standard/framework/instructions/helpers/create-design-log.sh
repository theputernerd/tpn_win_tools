#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <design-slug>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SLUG="$1"
TARGET="$ROOT_DIR/instructions/design-logs/$(date +%F)-$SLUG.md"

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"
validate_helper_name "$SLUG" "design slug"
reject_symlinks_under_root "$ROOT_DIR" "$TARGET"
require_regular_or_missing "$TARGET"

if [[ -f "$TARGET" ]]; then
  echo "Skipping existing file: $TARGET"
  exit 0
fi

cp "$ROOT_DIR/instructions/design-template.md" "$TARGET"
echo "Wrote: $TARGET"
