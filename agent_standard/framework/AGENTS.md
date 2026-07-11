# Agent Instructions

This repository uses a standard agent-assisted workflow for iteratively building
and improving a product over time. These rules are mandatory. They are
deliberately lightweight by default and scale up only when a task is risky.

## First contact: is the project initialised?

Run `./tasks.sh validate`. If it errors with "not defined", the project has not
been initialised yet. **Your first task is `project-init`:**

1. Establish what the project is (from the user, plus `instructions/product/overview.md`).
2. Choose the stack and record the decision in a design log.
3. Fill `instructions/project-commands.sh` so every verb
   (`setup build test lint run validate`) works.
4. Seed `instructions/product/overview.md` and `instructions/product/roadmap.md`.
5. Create the first module doc(s) with `instructions/helpers/add-module.sh`.

Everything else in this repo assumes `./tasks.sh validate` is a real gate, so
make it real before building features.

## Required reading before any work

- `instructions/README.md`
- `instructions/agent-contract.md`
- `instructions/escalation-policy.md`
- `instructions/global-conventions.md`
- `instructions/product/overview.md` and the relevant `instructions/product/modules/<m>/`
- The relevant `instructions/modules/<module>/module.md`
- Any relevant `instructions/project-conventions/`

## Choose a task tier first

Every task is one of three tiers. The tier sets how much process is required —
do not pay the full tax on a trivial change.

| Tier | Examples | Required artifacts |
|------|----------|--------------------|
| **trivial** | docs, comment, one-line obvious fix, formatting | one line in a session `action-log.md`; pass `./tasks.sh validate` |
| **standard** | a feature, a bug fix, a contained refactor | session log (plan + action log + handoff); `./tasks.sh validate`; update the module doc + changelog |
| **high-risk** | multi-module change, architecture, migration, security, concurrency | everything in standard **plus** a design log before coding, and honour every escalation trigger |

When unsure, pick the higher tier.

## Required workflow (standard / high-risk)

1. Classify the task and pick a tier.
2. Check `instructions/escalation-policy.md` triggers. If any fires, pause or escalate.
3. High-risk: write a design log before coding.
4. Open a session log: `instructions/helpers/create-session-log.sh <slug>`.
5. Write a plan before acting.
6. Log intent before, and result after, each material action.
7. Run `./tasks.sh validate` — it must exit 0.
8. Update the relevant module `module.md` and `changelog.md`, and the roadmap.
9. Write the handoff summary.

## Iteration loop

Product work is driven by `instructions/product/roadmap.md`, not ad hoc:
pick from the backlog → (design log if high-risk) → session log → build →
`validate` → changelog → move the item on the roadmap and note what's next.

## Reuse-first engineering

Prefer reusing/extending existing components over new parallel implementations.
If you deliberately choose a narrow fix, justify it in the session log.

## Completion rule

A standard/high-risk task is incomplete without: a tier, a plan before action,
continuous logging, a passing `./tasks.sh validate`, updated module doc +
changelog + roadmap, and a handoff summary.
