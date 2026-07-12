#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <convention-slug>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SLUG="$1"
TARGET="$ROOT_DIR/instructions/project-conventions/$SLUG.md"

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"
validate_helper_name "$SLUG" "convention slug"
reject_symlinks_under_root "$ROOT_DIR" "$TARGET"
require_regular_or_missing "$TARGET"

if [[ -f "$TARGET" ]]; then
  echo "Skipping existing file: $TARGET"
  exit 0
fi

cat > "$TARGET" <<'EOF'
# Project Convention

## Purpose
[Describe the repository-specific convention and when it applies]

## Rules
-

## Affected areas
-

## Validation implications
- How `./tasks.sh validate` (or a manual check) enforces or relates to this:

## Notes
-
EOF

echo "Wrote: $TARGET"
