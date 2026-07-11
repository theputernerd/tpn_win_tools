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

mkdir -p "$MODULE_DIR"
DST="$MODULE_DIR/overview.md"

if [[ -f "$DST" ]]; then
  echo "Skipping existing file: $DST"
  exit 0
fi

sed "s/<name>/$NAME/g" "$TEMPLATE" > "$DST"
echo "Wrote: $DST"
