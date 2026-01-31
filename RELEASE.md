# Release Checklist

## 1) Update versions and notes

- Bump bundle `VERSION`
- Bump tool versions in `scripts\<tool>\VERSION` as needed
- Update `RELEASE_NOTES.md` (latest-only notes)
- Update `scripts\<tool>\RELEASE_NOTES.md` (latest-only notes)
- Update `RELEASE_TEMPLATE.md` if you need to change the release body format
- Optional: add `scripts\<tool>\RELEASE_EXAMPLES.md` for tool-specific examples

## 2) Build

```bat
tools\deploy_release.cmd
```

Options:

```bat
tools\deploy_release.cmd /version 0.3.9 /y
tools\deploy_release.cmd /auto
tools\deploy_release.cmd /no-push /no-gh
```

Optional local install (build + install in one step):

```bat
BUILD_AND_INSTALL.cmd
```

## 3) Smoke test

```bat
for %f in (dist\*.exe) do "%f" --version
```

## 4) Commit and tag

- Commit source changes (do not commit `dist`)
- Tag the release (for example `v0.3.8`)

## 5) Publish

- Use `tools\publish_release.cmd -Tag vX.Y.Z` (requires `gh auth login`)
- Release body is generated from `RELEASE_TEMPLATE.md` and per-tool release notes
