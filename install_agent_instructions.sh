#!/usr/bin/env bash
set -euo pipefail

FORCE=0
ROOT_DIR="$(pwd)"
INSTR_DIR="$ROOT_DIR/instructions"
MODULES_DIR="$INSTR_DIR/modules"
SESSION_LOGS_DIR="$INSTR_DIR/session-logs"
HELPERS_DIR="$INSTR_DIR/helpers"
TEMPLATES_DIR="$INSTR_DIR/templates"

usage() {
  cat <<'EOF'
Usage: ./install_agent_instructions.sh [--force]

Creates a reusable instructions/ system in the current project root.

Options:
  --force     Overwrite existing managed files.
  -h, --help  Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

mkdir -p "$INSTR_DIR" "$MODULES_DIR" "$SESSION_LOGS_DIR" "$HELPERS_DIR" "$TEMPLATES_DIR"
echo "Creating instruction system under: $INSTR_DIR"

write_file() {
  local path="$1"
  local tmp

  tmp="$(mktemp)"
  cat > "$tmp"

  if [[ -f "$path" && "$FORCE" -ne 1 ]]; then
    echo "Skipping existing file: $path"
    rm -f "$tmp"
    return 0
  fi

  mkdir -p "$(dirname "$path")"
  mv "$tmp" "$path"
  echo "Wrote: $path"
}

write_executable() {
  local path="$1"

  write_file "$path"
  chmod +x "$path"
}

write_file "$INSTR_DIR/README.md" <<'EOF'
# Instructions System

This directory is the durable memory and operating contract for coding agents working on this project. All agents must read this directory before starting work. These files exist to make stateless or fresh sessions reliable, resumable, and consistent.

## Required startup sequence

Before making any code, config, schema, infrastructure, or test changes, the agent must:

1. Read `instructions/README.md`.
2. Read `instructions/agent-contract.md`.
3. Read `instructions/model-selection-policy.md`.
4. Read `instructions/global-conventions.md`.
5. Identify the affected modules.
6. Read the relevant files under `instructions/modules/<module>/`.
7. Open or create the current session log under `instructions/session-logs/`.
8. Write the model-fit assessment.
9. Write a plan before acting.

No implementation work may start before the plan is written.

## Core rules

- Documentation is part of the codebase.
- Planning is mandatory before action.
- Progress must be written continuously so a restart can resume safely.
- The agent must assess whether the current model is appropriate before starting work.
- If the current model is not suitable, the agent must pause and produce a pause report.
- The agent must preserve git state throughout the task.
- The agent must prefer reusable, composable, maintainable solutions over one-off or hacky solutions.
- The agent must reuse and extend existing abstractions where appropriate instead of duplicating similar logic.
- If behavior changes, the relevant docs must be updated before the task is complete.

## Directory layout

- `agent-contract.md` - mandatory workflow and stop conditions for every task.
- `model-selection-policy.md` - rules for deciding whether the current model is adequate.
- `global-conventions.md` - project-wide engineering conventions.
- `planning-template.md` - structure to use before acting.
- `logging-template.md` - structure for crash-safe logging and handoff.
- `modules/` - module-level knowledge, runbooks, interfaces, and change logs.
- `session-logs/` - per-task logs and checkpoints.
- `templates/` - reusable file templates.
- `helpers/` - helper scripts for maintaining this instruction system.

## Module layout

Each major module should have its own folder:

- `overview.md`
- `components.md`
- `interfaces.md`
- `runbook.md`
- `known-issues.md`
- `current-status.md`
- `changelog.md`

Use `instructions/helpers/add-module.sh <module-name>` to create one.

## Session logs

Each task should have its own folder under `instructions/session-logs/`, for example:

`instructions/session-logs/2026-04-17-fix-auth-timeout/`

Recommended files:

- `status.md` - latest resumable checkpoint
- `action-log.md` - append-only history
- `handoff.md` - pause/failure/completion summary

## Git policy summary

- Start from a clean working tree.
- Record the current branch and base commit.
- Work on a task branch.
- Preserve progress with checkpoint commits clearly labeled as unvalidated.
- Do not create a final validated commit until required checks pass.
- When something breaks, compare the current state against the base commit and the most recent checkpoint.

## Completion rule

A task is incomplete if any of the following are missing:

- model-fit assessment
- written plan before action
- crash-safe action log
- validation results
- required doc updates
- relevant module changelog update
- final handoff summary
EOF

write_file "$INSTR_DIR/agent-contract.md" <<'EOF'
# Agent Contract

This contract is mandatory for every agent session working in this project.

## Required lifecycle

1. Intake
2. Model suitability check
3. Planning
4. Execution
5. Validation
6. Documentation updates
7. Final handoff

The agent must not skip or reorder these phases.

## Non-negotiable rules

- Do not act before planning.
- Do not continue if the model is not suitable.
- Do not rely on memory alone; write progress as you go.
- Do not finish without validation.
- Do not finish without updating relevant docs.
- Do not present a hack, one-off patch, or duplicated logic as a complete solution when a reusable abstraction is appropriate.
- Do not create parallel implementations of the same idea when an existing component can be reused or extended safely.

## Mandatory startup steps

Before changing anything, the agent must:

1. Read the required top-level instruction files.
2. Identify affected modules.
3. Read the relevant module docs.
4. Create or open a session log.
5. Record branch, base commit, and current HEAD.
6. Classify the task.
7. Assess model fit.
8. Write a plan.

## Task classification

The agent must classify the task as one or more of:

- bug fix
- feature
- refactor
- architecture
- docs
- migration
- incident / debugging
- performance
- security

## Reuse-first engineering policy

The agent must optimize for maintainable reuse.

### Required behavior

- Look for existing components, utilities, services, patterns, and abstractions before creating new ones.
- Prefer extending an existing component over creating a nearly identical new one.
- Prefer shared utilities over duplicated logic.
- Prefer configuration, composition, or parameterization over copy-paste variation.
- Keep code general enough to be reused when the use case is likely to recur.
- Leave behind code that is easier to extend, test, and reason about.

### Forbidden behavior

- Do not hardcode values or special cases without documenting why they are necessary.
- Do not create duplicate helper functions that differ only trivially.
- Do not add one-off glue code when a reusable abstraction is appropriate.
- Do not bypass existing architecture unless the session log explains why and records the follow-up needed.

### If a narrow fix is chosen

If the agent intentionally chooses a narrow local fix instead of a more reusable abstraction, it must record:

- why the narrow fix was chosen
- why broader reuse was not appropriate now
- what follow-up would generalize the solution later

## Crash-safety requirements

The agent must be restart-safe.

- Write progress continuously, not only at the end.
- Record intent before each material action.
- Record the outcome immediately after the action.
- Keep the session status current at all times.
- Mark whether the repository may be in a partial state.
- A fresh agent must be able to resume using the logs and repo state alone.

## Checkpoint rule

The agent must write a checkpoint after any of:

- file modification
- command with side effects
- schema or config change
- test run
- blocker discovery
- plan change
- pause, failure, or completion

## Required execution pattern

For each material action:

1. Write intended action.
2. Perform action.
3. Write observed result.
4. Update current checkpoint.

## Pause conditions

The agent must stop and mark the task as `PAUSED` if:

- the current model is not adequate
- required docs are missing or contradictory
- the requested change exceeds safe scope
- validation cannot be completed
- the task has architectural ambiguity beyond the current model's reliable reasoning capacity
- the blast radius is high and the current model cannot justify the design confidently

## Pause report format

Every pause must include:

- reason for pause
- work completed so far
- current findings
- why the current model is insufficient, if relevant
- recommended next model or capability
- next suggested steps
- relevant files and commits

## Completion checklist

- [ ] Required docs were read
- [ ] Task was classified
- [ ] Model fit was assessed
- [ ] Plan was written before edits
- [ ] Session log was maintained continuously
- [ ] Required tests and checks were run
- [ ] Git state was recorded
- [ ] Relevant docs were updated
- [ ] Relevant module changelog was updated
- [ ] Final handoff was written
EOF

write_file "$INSTR_DIR/model-selection-policy.md" <<'EOF'
# Model Selection Policy

The agent must assess whether the current model is appropriate before doing any work.

## Goal

Use a model with enough reasoning depth, context handling, and reliability for the task. If the assigned model is not suitable, the agent must pause instead of proceeding blindly.

## Usually acceptable for a smaller or faster model

- documentation-only updates
- simple single-file changes
- small obvious bug fixes with clear scope
- linting or formatting fixes
- narrow test updates with low ambiguity
- straightforward mechanical refactors confined to one area

## Usually requires a larger or stronger model

- multi-module refactors
- architecture changes
- ambiguous bug reports
- root-cause analysis across subsystems
- distributed systems behavior
- concurrency, async, or state-heavy logic
- security-sensitive work
- migrations and data transformations
- performance work with tradeoffs
- tasks needing reasoning across many files or long instructions
- tasks requiring careful comparison against prior states or multiple checkpoints

## Mandatory pause conditions

The agent must pause before implementation if:

- the task spans multiple modules and the causal chain is unclear
- the agent cannot explain the likely failure mode confidently
- the task requires non-trivial design tradeoffs
- the change has high blast radius
- the context likely exceeds what the current model can track reliably
- the current model is repeatedly producing weak, inconsistent, or incomplete plans
- the task needs architecture-level judgment that the current model cannot justify convincingly

## Required written assessment

The session log must record:

- current model
- task classification
- adequacy assessment: `adequate` or `not adequate`
- reasoning
- capability gaps, if any
- whether work may proceed

## Rule

If the model is not adequate, the agent must stop after producing a useful pause report. It must not continue implementation work.
EOF

write_file "$INSTR_DIR/global-conventions.md" <<'EOF'
# Global Conventions

These conventions apply across the project unless a module-specific doc explicitly says otherwise.

## Engineering principles

- Prefer clarity over cleverness.
- Prefer simple, composable abstractions over special-case code.
- Prefer extension and reuse over duplication.
- Prefer maintainable generalization over narrow hacks when the pattern is likely to recur.
- Keep interfaces explicit.
- Keep side effects visible.
- Minimize blast radius.
- Make validation easy.

## Reuse and abstraction policy

Before adding new code, the agent must check whether the same or similar logic already exists. The agent should prefer, in order:

1. reuse an existing component unchanged
2. extend an existing component safely
3. extract shared behavior into a reusable abstraction
4. create a new component only when the above are not appropriate

If a new abstraction is introduced, the agent should make it clean enough for future reuse and document where it should be used.

## Documentation rules

- Docs must describe current reality, not only target design.
- Separate current implementation from planned architecture.
- Module docs should stay durable and high signal.
- Session logs hold volatile execution history and recovery context.
- Changelogs should be concise and append-only.

## Validation rules

Every task must record:

- tests run
- result
- manual verification performed
- whether restart is required
- whether migration is required
- unresolved risks

## Git conventions

Use these commit labels:

- `checkpoint: <summary> [unvalidated]`
- `validated: <summary>`

Checkpoint commits are allowed before full confirmation. Final validated commits are only allowed after required checks pass.

## Logging conventions

Each session log should be complete enough for handoff and restart, but it does not need to expose private chain-of-thought. Required logging content:

- material actions
- files inspected
- files changed
- decisions and rationale
- tests and outcomes
- blockers
- current checkpoint and next step

## When docs must be updated

Update docs whenever any of the following changed:

- architecture
- behavior
- interfaces
- runbook steps
- assumptions
- debugging knowledge
- known issues
- restart, migration, or testing requirements
EOF

write_file "$INSTR_DIR/planning-template.md" <<'EOF'
# Planning Template

## Task

[Restate the request clearly.]

## Requested outcome

[What should be true when this is done?]

## Task classification

- [ ] bug fix
- [ ] feature
- [ ] refactor
- [ ] architecture
- [ ] docs
- [ ] migration
- [ ] incident / debugging
- [ ] performance
- [ ] security

## Affected modules

- [module name]

## Docs reviewed

- instructions/README.md
- instructions/agent-contract.md
- instructions/model-selection-policy.md
- instructions/global-conventions.md
- instructions/modules/<module>/overview.md
- instructions/modules/<module>/runbook.md

## Model-fit assessment

Current model: [model]
Assessment: [adequate / not adequate]
Reasoning: [why]
Capability gaps: [if any]

## Understanding of the current system

[Concrete summary of the relevant current behavior and architecture.]

## Reuse assessment

Existing reusable elements reviewed:

- [component / utility / service]

Chosen approach regarding reuse:

- [reuse existing / extend existing / extract shared abstraction / create new component]

Reasoning: [Why this choice is the most maintainable option.]

## Proposed approach

1. ...
2. ...
3. ...

## Risks

- ...

## Validation plan

- automated tests:
- manual checks:
- restart required?:
- migration required?:

## Git plan

- task branch:
- base commit:
- expected checkpoint points:
EOF

write_file "$INSTR_DIR/logging-template.md" <<'EOF'
# Crash-Safe Logging Template

Use one folder per task under `instructions/session-logs/`. Recommended files:

- `status.md`
- `action-log.md`
- `handoff.md`

---

# status.md

```md
# Session Status
Task: [task]
Status: ACTIVE | PAUSED | FAILED | COMPLETE
Agent: [agent]
Model: [model]
Started: [timestamp]
Last updated: [timestamp]

## Git state
- Branch:
- Base commit:
- Current HEAD:
- Last known good commit:

## Current phase
- intake / planning / execution / validation / docs / handoff

## Current checkpoint
- Last completed step:
- Current next step:
- Safe to resume from:
- Repo may be in partial state: yes/no

## Docs reviewed
- ...

## Files inspected
- ...

## Files changed
- ...

## Tests run
- ...

## Outstanding work
- ...

## Risks / warnings
- ...

## Restart instructions
- First file to read:
- Next action:
- Preconditions / cautions:

## Expected next log entry
- [for example: VALIDATION_RESULT for <your-build-or-test-command>]
```

---

# action-log.md

```md
# Action Log

## [timestamp]
Type: PLAN | INTENT | INSPECT | CHANGE | TEST | STATE | BLOCKER | RESUME | PAUSE | COMPLETE
Details:
- ...
```

---

# handoff.md

```md
# Handoff
Status: PAUSED | FAILED | COMPLETE

## Summary
- ...

## What was completed
- ...

## What remains
- ...

## Current findings
- ...

## Git state
- Branch:
- Base commit:
- Current HEAD:
- Last known good commit:

## Validation state
- Tests run:
- Results:
- Manual checks:
- Restart required:
- Migration required:

## Recommended next steps
1. ...
2. ...
3. ...
```
EOF

write_file "$TEMPLATES_DIR/module-overview.md" <<'EOF'
# Overview

## Purpose

[What this module is for.]

## Responsibilities

- ...

## Non-responsibilities

- ...

## Dependencies

- ...

## Key files

- ...

## Data flow summary

- ...

## Last updated

- [date]
EOF

write_file "$TEMPLATES_DIR/module-components.md" <<'EOF'
# Components

## Major components

### [Component name]

- Purpose:
- Inputs:
- Outputs:
- Dependencies:
- Reuse opportunities / shared abstractions:

## Notes on composition

- ...
EOF

write_file "$TEMPLATES_DIR/module-interfaces.md" <<'EOF'
# Interfaces

## Public APIs

- ...

## Events / messages

- ...

## Database / storage contracts

- ...

## External integrations

- ...

## Invariants

- ...
EOF

write_file "$TEMPLATES_DIR/module-runbook.md" <<'EOF'
# Runbook

## Local run

- ...

## Tests

- ...

## Debugging

- ...

## Restart requirements

- ...

## Migration requirements

- ...

## Operational cautions

- ...
EOF

write_file "$TEMPLATES_DIR/module-known-issues.md" <<'EOF'
# Known Issues

## Active issues

- ...

## Fragile areas

- ...

## Temporary workarounds

- ...

## Suspected outdated assumptions

- ...
EOF

write_file "$TEMPLATES_DIR/module-current-status.md" <<'EOF'
# Current Status

## Stable entry points

- ...

## Active refactors

- ...

## Known broken paths

- ...

## Recent decisions

- ...

## Next likely cleanup targets

- ...
EOF

write_file "$TEMPLATES_DIR/module-changelog.md" <<'EOF'
# Changelog

## [date]

Task:
Summary:
Files changed:
Tests run:
Restart required:
Migration required:
Follow-up:
EOF

write_executable "$HELPERS_DIR/add-module.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <module-name>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
INSTR_DIR="$ROOT_DIR/instructions"
MODULE_NAME="$1"
MODULE_DIR="$INSTR_DIR/modules/$MODULE_NAME"
TEMPLATES_DIR="$INSTR_DIR/templates"

if [[ -e "$MODULE_DIR" ]]; then
  echo "Module already exists: $MODULE_DIR" >&2
  exit 1
fi

mkdir -p "$MODULE_DIR"
cp "$TEMPLATES_DIR/module-overview.md" "$MODULE_DIR/overview.md"
cp "$TEMPLATES_DIR/module-components.md" "$MODULE_DIR/components.md"
cp "$TEMPLATES_DIR/module-interfaces.md" "$MODULE_DIR/interfaces.md"
cp "$TEMPLATES_DIR/module-runbook.md" "$MODULE_DIR/runbook.md"
cp "$TEMPLATES_DIR/module-known-issues.md" "$MODULE_DIR/known-issues.md"
cp "$TEMPLATES_DIR/module-current-status.md" "$MODULE_DIR/current-status.md"
cp "$TEMPLATES_DIR/module-changelog.md" "$MODULE_DIR/changelog.md"

echo "Created module docs at: $MODULE_DIR"
EOF

write_executable "$HELPERS_DIR/create-session-log.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <task-name>" >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SESSION_LOGS_DIR="$ROOT_DIR/instructions/session-logs"
TASK_NAME="$1"
DATE_STR="$(date +%F)"
TASK_DIR="$SESSION_LOGS_DIR/${DATE_STR}-${TASK_NAME}"

if [[ -e "$TASK_DIR" ]]; then
  echo "Session log already exists: $TASK_DIR" >&2
  exit 1
fi

mkdir -p "$TASK_DIR"

cat > "$TASK_DIR/status.md" <<'EOF_STATUS'
# Session Status
Task:
Status: ACTIVE
Agent:
Model:
Started:
Last updated:

## Git state
- Branch:
- Base commit:
- Current HEAD:
- Last known good commit:

## Current phase
- intake

## Current checkpoint
- Last completed step:
- Current next step:
- Safe to resume from:
- Repo may be in partial state: no

## Docs reviewed
-

## Files inspected
-

## Files changed
-

## Tests run
-

## Outstanding work
-

## Risks / warnings
-

## Restart instructions
- First file to read: status.md
- Next action:
- Preconditions / cautions:

## Expected next log entry
- PLAN
EOF_STATUS

cat > "$TASK_DIR/action-log.md" <<'EOF_ACTION'
# Action Log
EOF_ACTION

cat > "$TASK_DIR/handoff.md" <<'EOF_HANDOFF'
# Handoff
Status: PAUSED

## Summary
-

## What was completed
-

## What remains
-

## Current findings
-

## Git state
- Branch:
- Base commit:
- Current HEAD:
- Last known good commit:

## Validation state
- Tests run:
- Results:
- Manual checks:
- Restart required:
- Migration required:

## Recommended next steps
1. ...
2. ...
3. ...
EOF_HANDOFF

echo "Created session log: $TASK_DIR"
EOF

touch "$SESSION_LOGS_DIR/.gitkeep"

echo "Done."
echo
echo "Next steps:"
echo " 1. Review instructions/README.md"
echo " 2. Create module docs with: instructions/helpers/add-module.sh <module-name>"
echo " 3. Create a task log with: instructions/helpers/create-session-log.sh <task-name>"
