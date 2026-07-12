# Agent Contract

Mandatory for every session. Process scales with the task **tier**; do not apply
high-risk ceremony to a trivial change, and do not skip it on a risky one.

## Tiers

| Tier | When | Required |
|------|------|----------|
| trivial | docs, comments, formatting, a single obvious low-blast-radius fix | one `action-log.md` line; `./tasks.sh validate` passes |
| standard | a feature, a bug fix, a contained refactor | session log (plan + action log + handoff); `validate`; applicable documentation updates |
| high-risk | multi-module, architecture, migration, security, concurrency, high blast radius | standard **plus** a design log before coding, **plus** every escalation trigger honoured |

Pick the higher tier when unsure. Record the tier in the plan and `status.md`.

## Lifecycle (standard / high-risk)

1. Intake and tier selection.
2. Escalation check (`escalation-policy.md`).
3. Design exploration + decision (high-risk, or when direction is unsettled).
4. Planning (`planning-template.md`).
5. Execution with continuous logging.
6. Validation: `./tasks.sh validate` must exit 0.
7. Documentation: apply the documentation triggers below.
8. Handoff.

## Non-negotiable rules

- Do not act before planning (standard/high-risk).
- Do not proceed past a fired escalation trigger without pausing/escalating.
- Do not rely on memory alone; write progress as you go.
- Do not call a task done until `./tasks.sh validate` passes.
- Do not finish without the tier's required doc updates.
- Do not create a parallel implementation when an existing component can be
  reused or safely extended. If you choose a narrow fix, record why in the log.

## Documentation triggers

- Update `module.md` (+ `verified-against:`) when its documented behavior,
  interfaces, invariants, or operational constraints changed.
- Update `changelog.md` for user-visible or operationally significant changes,
  compatibility/migration work, and important defect fixes.
- Update `product/roadmap.md` only when planned scope, priorities, status, or
  product direction changed. Do not invent roadmap entries for ordinary fixes.
- Every meaningful code change still records its validation result.

## Task classification

Tag each task with one or more of: design, bug fix, feature, refactor,
architecture, docs, migration, incident/debugging, performance, security,
infra/ops. Classification informs the tier.

## Crash-safety

- Record intent before, and outcome after, each material action.
- Keep `status.md` current; mark whether the repo may be in a partial state.
- A fresh agent must be able to resume from the logs and repo state alone.

Write a checkpoint after any: file modification, side-effecting command, schema/
config change, test/validate run, blocker, plan or design change, pause, or
completion.

## Definition of done

`./tasks.sh validate` exits 0, the tier's artifacts exist, triggered
documentation is updated, and the handoff is written. When a module doc changes,
its `verified-against:` marker names the existing implementation commit used as
the review baseline; the doc change also covers its accompanying diff.
