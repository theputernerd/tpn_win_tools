# Logging Template

Per-task directory under `instructions/session-logs/`, created by
`helpers/create-session-log.sh <slug>`. Trivial tasks may use only a single
`action-log.md` entry; standard/high-risk tasks use all three files.

## status.md

```md
# Session Status

Task:
Tier: trivial | standard | high-risk
Status: ACTIVE | PAUSED | FAILED | COMPLETE
Agent / Model:
Started / Last updated:

## Current phase
- intake / planning / design / execution / validation / docs / handoff

## Git state
- Branch / Base commit / Current HEAD / Last checkpoint / Last known-good:

## Current checkpoint
- Last completed step:
- Current next step:
- Repo may be in partial state: yes/no
- Expected next log entry:

## Validation
- Last `./tasks.sh validate` result:

## Outstanding work / Risks:
-

## Restart instructions
- First file to read / next action / cautions:
```

## action-log.md

```md
# Action Log

## YYYY-MM-DDTHH:MM:SSZ
Type: PLAN | INTENT | INSPECT | CHANGE | VALIDATE | STATE | BLOCKER | RESUME | PAUSE | COMPLETE
Details:
-
```

## handoff.md

```md
# Handoff

Status: ACTIVE | PAUSED | FAILED | COMPLETE

## Summary / What was finished / What remains:
-

## Validation status
- `./tasks.sh validate`:

## Git state
- Branch / Base / HEAD / Last checkpoint / Last known-good:

## Resume notes
-
```
