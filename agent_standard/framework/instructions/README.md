# Instructions System

The durable operating contract and memory layer for agent-assisted work in this
repository. It exists to make fresh sessions reliable, resumable, and auditable
while iteratively building and improving a product.

## Startup sequence

1. Run `./tasks.sh validate`. If it errors "not defined", do the **project-init**
   task first (see `AGENTS.md`).
2. Read `README.md`, `agent-contract.md`, `escalation-policy.md`, `global-conventions.md`.
3. Read `product/overview.md`, `product/roadmap.md`, and relevant product modules.
4. Read the relevant `modules/<module>/module.md`.
5. Classify the task and pick a **tier** (trivial / standard / high-risk).
6. Check escalation triggers.
7. High-risk: create a design log. Then open a session log and write a plan.

## Directory layout

- `AGENTS.md` (repo root) — the mandatory workflow, mirrored to `CLAUDE.md`.
- `tasks.sh` (repo root) — the stable command interface (`setup build test lint run validate`).
- `instructions/project-commands.sh` — where those commands are actually defined (user content).
- `agent-contract.md` — lifecycle, tiers, stop conditions.
- `escalation-policy.md` — objective triggers that force a pause/escalate.
- `global-conventions.md` — cross-project engineering rules.
- `planning-template.md`, `logging-template.md`, `design-template.md` — structures.
- `templates/` — the module/product-module doc templates helpers copy from.
- `modules/<module>/` — how each implementation module currently works (`module.md` + `changelog.md`).
- `product/` — product intent: `overview.md`, `roadmap.md`, `modules/<m>/`.
- `project-conventions/` — repo-specific conventions (put customisation here, not in AGENTS.md).
- `design-logs/` — design exploration, tradeoffs, decisions.
- `session-logs/` — per-task execution logs and recovery context.
- `helpers/` — scripts to create logs/modules/conventions and check compliance.

## Product docs vs module docs

- `product/` = what the system should do (intent, requirements, roadmap).
- `modules/` = how the current implementation actually works.

Keep them separate. Each `module.md` carries a `verified-against:` marker (see
`global-conventions.md`) so drift from the code becomes visible; run
`helpers/check-session.sh` to surface stale docs and missing logs.

## Upgrading the framework

Framework-managed files can be refreshed from a newer `framework/` with
`bootstrap_agent_standard_v4.sh --upgrade`. User content
(`project-commands.sh`, product docs, and everything you author under
`session-logs/`, `design-logs/`, `modules/`, `product/modules/`,
`project-conventions/`) is never overwritten.

## Completion rule

If the required tier's artifacts, a passing `./tasks.sh validate`, or the
doc/roadmap updates are missing, the task is incomplete.
