#!/usr/bin/env bash

# Shared input and path-safety checks for framework helpers.

helper_die() {
  echo "ERROR: $*" >&2
  return 1
}

validate_helper_name() {
  local value="$1"
  local label="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || [[ "$value" == "." || "$value" == ".." ]]; then
    helper_die "$label must use only letters, numbers, '.', '_' or '-', must start with a letter or number, and cannot be '.' or '..': $value"
  fi
}

validate_task_tier() {
  case "$1" in
    trivial|standard|high-risk) ;;
    *) helper_die "tier must be one of: trivial, standard, high-risk: $1" ;;
  esac
}

reject_symlinks_under_root() {
  local root="${1%/}"
  local target="$2"
  local rel current part
  local -a parts

  case "$target" in
    "$root"|"$root"/*) ;;
    *) helper_die "destination escapes project root: $target"; return 1 ;;
  esac

  current="$root"
  if [[ -L "$current" ]]; then
    helper_die "refusing to use symlinked project root: $current"
    return 1
  fi

  [[ "$target" == "$root" ]] && return 0
  rel="${target#"$root"/}"
  IFS='/' read -r -a parts <<< "$rel"
  for part in "${parts[@]}"; do
    current="$current/$part"
    if [[ -L "$current" ]]; then
      helper_die "refusing to write through symlink: $current"
      return 1
    fi
  done
}

require_directory_or_missing() {
  local path="$1"
  if [[ -e "$path" && ! -d "$path" ]]; then
    helper_die "expected a directory or missing path: $path"
  fi
}

require_regular_or_missing() {
  local path="$1"
  if [[ -e "$path" && ! -f "$path" ]]; then
    helper_die "expected a regular file or missing path: $path"
  fi
}
