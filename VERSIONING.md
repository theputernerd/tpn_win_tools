# Versioning and Release Automation

This project uses a **file-based versioning model** with optional local Git automation.
The design is intentional: simple, explicit, and robust over long machine lifetimes.

---

## Source of truth

### VERSION
`VERSION` contains the **version number only**.

Example:
```
0.2.0
```

This value is used by:
- `ttree --version`
- JSON output
- Self-test logs

No descriptions, metadata, or formatting belong in this file.

---

### RELEASE_NOTES.md
`RELEASE_NOTES.md` contains the **human description** of the release.

Example:
```md
## 0.2.0
- Added --json output
- Improved gitignore handling
- Minor internal refactor
```

This file is used for:
- Commit messages (optional automation)
- Annotated Git tag descriptions (optional automation)

---

## Normal workflow (no automation required)

This is always sufficient:

1. Update `VERSION`
2. Update `RELEASE_NOTES.md`
3. Commit the changes

The project does **not** depend on Git tags to run or build.

---

## Optional: automatic commit + tag automation (local)

Developers may choose to enable local Git hooks that:

- Append `RELEASE_NOTES.md` into the commit message when `VERSION` changes
- Automatically create an **annotated Git tag** (`vX.Y.Z`)
- Use the release notes as the tag description

This automation is:
- Local-only
- Developer-controlled
- Not enforced by the repository
- Not required for CI or builds

This avoids hidden behavior while still removing repetitive work.

---

## One-time setup (Windows / PowerShell)

This setup ensures **all new Git repositories** on the machine automatically get the hooks.

### 1. Create a global Git template directory

```powershell
mkdir $env:USERPROFILE\.git-templates\hooks
```

### 2. Add hook files (no extensions)

Create these files:

```
%USERPROFILE%\.git-templates\hooks\prepare-commit-msg
%USERPROFILE%\.git-templates\hooks\post-commit
```

(Contents are standard PowerShell Git hooks; see repository history or documentation.)

### 3. Enable the template globally

```powershell
git config --global init.templateDir "$env:USERPROFILE\.git-templates"
```

After this:
- Any `git init` (including from PyCharm) installs the hooks automatically
- Existing repositories must copy the hooks once if desired

---

## Important notes

- Git hooks do **not** sync with the repository by design
- CI does **not** rely on Git tags
- Git tags are convenience metadata, not a build input
- PyCharm hides `.git/` by default; this is expected behavior

---

## Design rationale

- `VERSION` is machine-readable and stable
- Release meaning lives outside runtime code
- Git remains a metadata layer, not a dependency
- The workflow survives machine replacement years later

This structure favors clarity over cleverness.
