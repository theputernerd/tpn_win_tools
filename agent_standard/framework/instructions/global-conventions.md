# Global Conventions

Apply across the project unless a `project-conventions/` or module doc explicitly
overrides them.

## Engineering principles

- Prefer clarity over cleverness; simple composable abstractions over special cases.
- Prefer reuse and safe extension over duplication and parallel implementations.
- Keep interfaces explicit and side effects visible; minimise blast radius.
- Keep project-specific logic out of generic shared components.
- Understand the system goal before optimising a local component.

## Reuse and abstraction, in order of preference

1. Reuse an existing component unchanged.
2. Extend an existing component safely.
3. Extract shared behaviour into a reusable abstraction.
4. Create something new only when the above do not fit — and document where it should be used.

## The command contract

`./tasks.sh` is the only supported way to build/test/lint/run/validate this repo.
Define the actual commands in `instructions/project-commands.sh`. Do not scatter
build knowledge across docs — point at the verbs. `validate` is the completion gate.

## Configuration

- Do not hardcode paths, environment-specific values, or dataset-specific logic
  in core reusable modules.
- Prefer config files or injected parameters for anything that varies by
  environment, dataset, model, or experiment.

## Documentation and drift control

- Docs describe current reality, not just target design.
- `product/` holds intent; `modules/` holds how the implementation works; session
  logs hold volatile execution history; design logs hold decisions.
- Every `module.md` starts with a marker:

  ```
  verified-against: <short-commit>   # the commit at which this doc was last confirmed true
  ```

  When you change a module, re-confirm its `module.md` and update this to the new
  commit in the same change. `helpers/check-session.sh` flags docs whose marker
  has fallen far behind HEAD so drift is visible instead of silent.
- Changelogs are concise and append-only.

## Validation

Each standard/high-risk task records: what `./tasks.sh validate` did, the result,
any manual checks, whether restart or migration is required, and whether the
current state is known-good or partial.

## Git

- Start from a clean tree when possible; record branch, base commit, and HEAD.
- Use an isolated task branch when appropriate.
- Keep progress with checkpoint commits labelled `[unvalidated]` when needed.
- Do not create a final validated commit until `./tasks.sh validate` passes.
- On regression, compare against the base commit, the latest checkpoint, and the
  last known-good state.

## Notebooks

Notebooks are for inspection/visualisation only. Do not hide core logic in them.
