#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP="$ROOT_DIR/bootstrap_agent_standard_v4.sh"
TMP_ROOT="$(mktemp -d)"
PASSED=0
FAILED=0

cleanup() {
  rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
  echo "PASS: $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "FAIL: $1" >&2
  FAILED=$((FAILED + 1))
}

assert_file() {
  [[ -f "$1" ]] || { echo "missing file: $1" >&2; return 1; }
}

assert_not_exists() {
  [[ ! -e "$1" && ! -L "$1" ]] || { echo "unexpected path: $1" >&2; return 1; }
}

new_project() {
  local name="$1"
  local dir="$TMP_ROOT/$name"
  mkdir -p "$dir"
  printf 'application sentinel\n' > "$dir/app.txt"
  printf '%s' "$dir"
}

run_bootstrap() {
  local project="$1"
  shift
  (cd "$project" && "$BOOTSTRAP" "$@")
}

test_dry_run_is_mutation_free() {
  local project output before after
  project="$(new_project dry-run)"
  before="$(find "$project" -mindepth 1 -printf '%P %y %l\n' | sort)"
  output="$(run_bootstrap "$project" --dry-run 2>&1)" || return 1
  after="$(find "$project" -mindepth 1 -printf '%P %y %l\n' | sort)"
  [[ "$before" == "$after" ]] || return 1
  [[ "$output" == *"Dry run complete. No files were changed."* ]] || return 1
  [[ "$output" == *"SEED    instructions/project-commands.sh"* ]] || return 1
}

test_noninteractive_requires_confirmation() {
  local project
  project="$(new_project confirmation)"
  if run_bootstrap "$project" >/dev/null 2>&1; then
    return 1
  fi
  assert_not_exists "$project/AGENTS.md"
  assert_not_exists "$project/instructions"
}

test_fresh_install() {
  local project src rel
  project="$(new_project fresh)"
  mkdir -p "$project/executive_assistant"
  printf 'nested project process\n' > "$project/executive_assistant/CLAUDE.md"
  run_bootstrap "$project" --yes >/dev/null || return 1
  assert_file "$project/AGENTS.md" || return 1
  assert_file "$project/tasks.sh" || return 1
  assert_file "$project/instructions/helpers/_common.sh" || return 1
  [[ -L "$project/CLAUDE.md" ]] || return 1
  [[ "$(readlink "$project/CLAUDE.md")" == "AGENTS.md" ]] || return 1
  [[ "$(cat "$project/.framework-version")" == "4.1.0" ]] || return 1
  [[ "$(cat "$project/app.txt")" == "application sentinel" ]] || return 1
  [[ "$(cat "$project/executive_assistant/CLAUDE.md")" == "nested project process" ]] || return 1
  while IFS= read -r -d '' src; do
    rel="${src#"$ROOT_DIR/framework"/}"
    cmp -s "$src" "$project/$rel" || return 1
  done < <(find "$ROOT_DIR/framework" -type f -print0)
}

test_repeated_install_refuses_without_changes() {
  local project before after
  project="$(new_project repeated)"
  run_bootstrap "$project" --yes >/dev/null || return 1
  before="$(find "$project" -type f -exec sha256sum {} + | sort -k2)"
  if run_bootstrap "$project" --yes >/dev/null 2>&1; then
    return 1
  fi
  after="$(find "$project" -type f -exec sha256sum {} + | sort -k2)"
  [[ "$before" == "$after" ]]
}

test_copy_claude() {
  local project
  project="$(new_project copy-claude)"
  run_bootstrap "$project" --yes --copy-claude >/dev/null || return 1
  [[ -f "$project/CLAUDE.md" && ! -L "$project/CLAUDE.md" ]] || return 1
  cmp -s "$project/AGENTS.md" "$project/CLAUDE.md"
}

test_bootstrap_invoked_through_symlink() {
  local project launcher
  project="$(new_project symlink-launcher)"
  launcher="$TMP_ROOT/bootstrap-link.sh"
  ln -s "$BOOTSTRAP" "$launcher"
  (cd "$project" && "$launcher" --yes >/dev/null) || return 1
  assert_file "$project/AGENTS.md"
}

test_reserved_path_conflict() {
  local project
  project="$(new_project conflict)"
  mkdir -p "$project/instructions"
  printf 'keep me\n' > "$project/instructions/existing.txt"
  if run_bootstrap "$project" --yes >/dev/null 2>&1; then
    return 1
  fi
  [[ "$(cat "$project/instructions/existing.txt")" == "keep me" ]] || return 1
  assert_not_exists "$project/AGENTS.md"
}

test_existing_claude_process_is_preserved() {
  local project
  project="$(new_project existing-claude)"
  printf 'custom project instructions\n' > "$project/CLAUDE.md"
  if run_bootstrap "$project" --yes >/dev/null 2>&1; then
    return 1
  fi
  [[ "$(cat "$project/CLAUDE.md")" == "custom project instructions" ]] || return 1
  assert_not_exists "$project/AGENTS.md" || return 1
  assert_not_exists "$project/instructions"
}

test_final_symlink_is_rejected() {
  local project external
  project="$(new_project final-symlink)"
  external="$TMP_ROOT/external-agents"
  printf 'outside\n' > "$external"
  ln -s "$external" "$project/AGENTS.md"
  if run_bootstrap "$project" --yes >/dev/null 2>&1; then
    return 1
  fi
  [[ "$(cat "$external")" == "outside" ]]
}

test_parent_symlink_is_rejected() {
  local project external
  project="$(new_project parent-symlink)"
  external="$TMP_ROOT/external-instructions"
  mkdir -p "$external"
  ln -s "$external" "$project/instructions"
  if run_bootstrap "$project" --yes >/dev/null 2>&1; then
    return 1
  fi
  [[ -z "$(find "$external" -mindepth 1 -print -quit)" ]]
}

test_unsafe_legacy_flags_are_disabled() {
  local project
  project="$(new_project legacy-flags)"
  if run_bootstrap "$project" --upgrade >/dev/null 2>&1; then
    return 1
  fi
  assert_not_exists "$project/AGENTS.md" || return 1
  if run_bootstrap "$project" --force >/dev/null 2>&1; then
    return 1
  fi
  assert_not_exists "$project/instructions"
}

test_helpers_validate_names_and_tiers() {
  local project helper
  project="$(new_project helpers)"
  run_bootstrap "$project" --yes >/dev/null || return 1
  helper="$project/instructions/helpers"
  "$helper/add-module.sh" safe_module >/dev/null || return 1
  assert_file "$project/instructions/modules/safe_module/module.md" || return 1
  if "$helper/add-module.sh" '../escape' >/dev/null 2>&1; then return 1; fi
  if "$helper/create-project-convention.sh" 'x/../../escape' >/dev/null 2>&1; then return 1; fi
  if "$helper/create-session-log.sh" bad-tier impossible >/dev/null 2>&1; then return 1; fi
  assert_not_exists "$project/escape.md"
}

test_helpers_reject_symlinked_destination() {
  local project helper external
  project="$(new_project helper-symlink)"
  run_bootstrap "$project" --yes >/dev/null || return 1
  helper="$project/instructions/helpers"
  external="$TMP_ROOT/external-modules"
  mkdir -p "$external"
  rm "$project/instructions/product/modules/.gitkeep"
  rmdir "$project/instructions/product/modules"
  ln -s "$external" "$project/instructions/product/modules"
  if "$helper/add-product-module.sh" unsafe >/dev/null 2>&1; then return 1; fi
  [[ -z "$(find "$external" -mindepth 1 -print -quit)" ]]
}

test_session_selection() {
  local project helper output
  project="$(new_project sessions)"
  run_bootstrap "$project" --yes >/dev/null || return 1
  helper="$project/instructions/helpers"
  sed -i 's/cmd_validate() { _undefined; }/cmd_validate() { :; }/' "$project/instructions/project-commands.sh"
  "$helper/create-session-log.sh" z-complete standard >/dev/null || return 1
  sed -i 's/^Status: ACTIVE$/Status: COMPLETE/' "$project/instructions/session-logs/$(date +%F)-z-complete/status.md"
  "$helper/create-session-log.sh" a-active standard >/dev/null || return 1
  output="$("$helper/check-session.sh" --strict 2>&1)" || return 1
  [[ "$output" == *"session $(date +%F)-a-active"* ]] || return 1

  "$helper/create-session-log.sh" b-active standard >/dev/null || return 1
  if "$helper/check-session.sh" --strict >/dev/null 2>&1; then return 1; fi
  "$helper/check-session.sh" --strict --session "$(date +%F)-z-complete" >/dev/null 2>&1
}

tests=(
  test_dry_run_is_mutation_free
  test_noninteractive_requires_confirmation
  test_fresh_install
  test_repeated_install_refuses_without_changes
  test_copy_claude
  test_bootstrap_invoked_through_symlink
  test_reserved_path_conflict
  test_existing_claude_process_is_preserved
  test_final_symlink_is_rejected
  test_parent_symlink_is_rejected
  test_unsafe_legacy_flags_are_disabled
  test_helpers_validate_names_and_tiers
  test_helpers_reject_symlinked_destination
  test_session_selection
)

for test_name in "${tests[@]}"; do
  if "$test_name"; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
done

echo ""
echo "Tests passed: $PASSED"
echo "Tests failed: $FAILED"
[[ "$FAILED" -eq 0 ]]
