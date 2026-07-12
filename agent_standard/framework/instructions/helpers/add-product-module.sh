#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <module-name>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
NAME="$1"
MODULE_DIR="$ROOT_DIR/instructions/product/modules/$NAME"
TEMPLATE="$ROOT_DIR/instructions/templates/product-module.md"

# shellcheck source=_common.sh
source "$(dirname "$0")/_common.sh"
validate_helper_name "$NAME" "product module name"
reject_symlinks_under_root "$ROOT_DIR" "$MODULE_DIR"
require_directory_or_missing "$MODULE_DIR"

mkdir -p "$MODULE_DIR"
DST="$MODULE_DIR/overview.md"

reject_symlinks_under_root "$ROOT_DIR" "$DST"
require_regular_or_missing "$DST"

if [[ -f "$DST" ]]; then
  echo "Skipping existing file: $DST"
  exit 0
fi

sed "s|<name>|$NAME|g" "$TEMPLATE" > "$DST"
echo "Wrote: $DST"
