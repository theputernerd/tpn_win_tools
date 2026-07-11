# agent_standard

Generic, reusable agent-instructions framework for iteratively building and
improving a product with AI coding agents. Run the installer **before** a project
is built; agents then use the installed contract to design, build, and validate
the system over time.

Successor to the repo-root `install_agent_instructions.sh` (v1/v2) and
`bootstrap_agent_standard.sh` (v3). Unlike those, the framework content lives as
real, editable files under `framework/` (not an inline heredoc), and existing
projects can be upgraded in place without clobbering user content.

## One-time setup: symlink the bootstrap script into ~

```bash
cd ~
/path/to/agent_standard/create_symlink.sh
```

Creates `~/bootstrap_agent_standard_v4.sh` as a symlink to the real script, so
it can be run from any project root afterwards.

## Install into a project

```bash
cd <your-project-root>
~/bootstrap_agent_standard_v4.sh          # fresh install
~/bootstrap_agent_standard_v4.sh --upgrade  # refresh managed files later
```

`--upgrade` overwrites only framework-managed files. User content is never
touched: `instructions/project-commands.sh`, `instructions/product/overview.md`,
`instructions/product/roadmap.md`, and anything authored under
`session-logs/`, `design-logs/`, `modules/`, `product/modules/`, and
`project-conventions/`.

## Layout

- `bootstrap_agent_standard_v4.sh` — the installer (copies `framework/` into the target).
- `create_symlink.sh` — one-time setup that symlinks the bootstrap script into
  the directory it's run from (e.g. `~`).
- `framework/` — source of truth for everything installed, versioned by
  `framework/.framework-version`. Edit these files to evolve the framework, then
  `--upgrade` projects to pull the changes.

## What the installed framework gives a project

- `tasks.sh` — a stable command contract (`setup build test lint run validate`);
  actual commands are defined per-project in `instructions/project-commands.sh`
  during the first `project-init` task. `validate` is the completion gate.
- Task **tiers** (trivial / standard / high-risk) so process scales with risk.
- `escalation-policy.md` — objective triggers that force a pause/escalate.
- Per-module `module.md` + `changelog.md` with a `verified-against:` marker;
  `helpers/check-session.sh` flags doc drift and missing session logs
  (wire it as a `--strict` git pre-commit hook to enforce).
- `product/roadmap.md` to drive the iteration loop.

See `framework/instructions/README.md` for the full contract.
