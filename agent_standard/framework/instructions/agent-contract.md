# Agent Contract

Mandatory for every session. Process scales with the task **tier**; do not apply
high-risk ceremony to a trivial change, and do not skip it on a risky one.

## Tiers

| Tier | When | Required |
|------|------|----------|
| trivial | docs, comments, formatting, a single obvious low-blast-radius fix | one `action-log.md` line; `./tasks.sh validate` passes |
| standard | a feature, a bug fix, a contained refactor | session log (plan + action log + handoff); `validate`; update module doc + changelog + roadmap |
| high-risk | multi-module, architecture, migration, security, concurrency, high blast radius | standard **plus** a design log before coding, **plus** every escalation trigger honoured |

Pick the higher tier when unsure. Record the tier in the plan and `status.md`.

## Lifecycle (standard / high-risk)

1. Intake and tier selection.
2. Escalation check (`escalation-policy.md`).
3. Design exploration + decision (high-risk, or when direction is unsettled).
4. Planning (`planning-template.md`).
5. Execution with continuous logging.
6. Validation: `./tasks.sh validate` must exit 0.
7. Documentation: update the module `module.md` (+ its `verified-against:` marker),
   `changelog.md`, and `product/roadmap.md`.
8. Handoff.

## Non-negotiable rules

- Do not act before planning (standard/high-risk).
- Do not proceed past a fired escalation trigger without pausing/escalating.
- Do not rely on memory alone; write progress as you go.
- Do not call a task done until `./tasks.sh validate` passes.
- Do not finish without the tier's required doc updates.
- Do not create a parallel implementation when an existing component can be
  reused or safely extended. If you choose a narrow fix, record why in the log.

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

`./tasks.sh validate` exits 0, the tier's artifacts exist, the module doc's
`verified-against:` marker points at the current commit, and the handoff is
written.
