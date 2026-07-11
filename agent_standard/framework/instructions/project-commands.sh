#!/usr/bin/env bash
# project-commands.sh - USER CONTENT. Single source of truth for how to build,
# test, run, and validate THIS project. Filled in during the project-init task.
#
# ./tasks.sh <verb> calls cmd_<verb>. Keep each function to the real command(s)
# for this repo. Prefer calling the project's own tooling over reimplementing it.
#
# Until a function is defined for real it uses _undefined, so ./tasks.sh reports
# clearly instead of silently passing.

_undefined() {
  echo "This command is not defined yet. Edit instructions/project-commands.sh" >&2
  echo "(project-init task) and replace the _undefined body for cmd_${FUNCNAME[1]#cmd_}." >&2
  return 1
}

# Install dependencies / prepare a local dev environment.
cmd_setup()    { _undefined; }

# Compile / bundle / generate build artifacts. No-op is fine for interpreted
# projects: replace the body with `:` (true) if there is nothing to build.
cmd_build()    { _undefined; }

# Run the automated test suite.
cmd_test()     { _undefined; }

# Static checks: linters, type checks, formatters in --check mode.
cmd_lint()     { _undefined; }

# Run the app / service locally.
cmd_run()      { _undefined; }

# THE COMPLETION GATE. A task is not "done" until this exits 0.
# Typically: lint, then test, then build. Example once defined:
#   cmd_validate() { cmd_lint && cmd_test && cmd_build; }
cmd_validate() { _undefined; }
