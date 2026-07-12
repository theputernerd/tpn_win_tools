# agent_standard

Generic, reusable agent-instructions framework for iteratively building and
improving a product with AI coding agents. Run the installer **before** a project
is built; agents then use the installed contract to design, build, and validate
the system over time.

Successor to the repo-root `install_agent_instructions.sh` (v1/v2) and
`bootstrap_agent_standard.sh` (v3). Unlike those, the framework content lives as
real, editable files under `framework/` rather than an inline heredoc.

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
~/bootstrap_agent_standard_v4.sh --dry-run  # mutation-free preview
~/bootstrap_agent_standard_v4.sh            # review and confirm interactively
# or, after reviewing the preview:
~/bootstrap_agent_standard_v4.sh --yes       # non-interactive confirmation
```

The bootstrap script is a fresh initializer, not an upgrade or merge tool. It
can initialize a new project or an existing codebase that does not already use
the reserved root paths. If `.framework-version`, `AGENTS.md`, `CLAUDE.md`,
`tasks.sh`, or `instructions/` already exists, it stops without changing files.
After initialization, all installed files belong to the project; future
framework changes must be reviewed and applied manually.

## Layout

- `bootstrap_agent_standard_v4.sh` — the installer (copies `framework/` into the target).
- `create_symlink.sh` — one-time setup that symlinks the bootstrap script into
  the directory it's run from (e.g. `~`).
- `framework/` — source of truth for new initializations, versioned by
  `framework/.framework-version`. Edits affect future initializations only.

## What the installed framework gives a project

- `tasks.sh` — a stable command contract (`setup build test lint run validate`);
  actual commands are defined per-project in `instructions/project-commands.sh`
  during the first `project-init` task. `validate` is the completion gate.
- Task **tiers** (trivial / standard / high-risk) so process scales with risk.
- `escalation-policy.md` — objective triggers that force a pause/escalate.
- Per-module `module.md` + `changelog.md` with a `verified-against:` marker;
  `helpers/check-session.sh` flags doc drift and missing session logs
  (wire it as a `--strict` git pre-commit hook to enforce).
- `product/roadmap.md` to drive planned product iteration without forcing
  synthetic entries for ordinary fixes.

See `framework/instructions/README.md` for the full contract.

## Development checks

Run the dependency-free regression suite with:

```bash
bash tests/run.sh
```

It exercises initialization, previews, collisions, symlink rejection, helper
path safety, and current-session selection in disposable temporary projects.
