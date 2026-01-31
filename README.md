# tpn_win_tools

tpn_win_tools is a small Windows tool bundle built from Python entrypoints in `scripts`.
The build produces standalone EXEs in `dist` and can install them onto the user PATH.

## Toolset

- `ttree` - Enhanced tree listing with excludes, JSON output, and self-test. See `scripts/ttree/README.md`.
- `wget` - Wget-like downloader with resume, recursion, and optional multi-threading. See `scripts/wget/README.md`.

## Repo layout

- `scripts` - tool entrypoints and per-tool folders
- `tools` - build and install scripts
- `build` - PyInstaller work output
- `dist` - compiled EXEs

## Adding or updating tools

1. Create a tool entrypoint named after the tool:
   - `scripts\tool.py`
   - `scripts\tool\tool.py`
2. Keep other modules under subfolders and avoid extra entrypoints in `scripts` root.
3. Add or update a tool README at `scripts\tool\README.md`.
4. Update this Toolset list when adding a new tool.
5. If the tool needs extra dependencies, add a per-tool file:
   - `scripts\tool\requirements.txt` for folder tools
   - `scripts\tool.requirements.txt` for root tools
6. If the tool uses a shared build env, add those dependencies to the matching root requirements file:
   - `.venv_py<major>.<minor>` uses `requirements_py<major>.<minor>.txt`
7. Add `scripts\tool\VERSION` and keep it in sync with the tool changes.
8. Add `scripts\tool\RELEASE_NOTES.md` and keep it updated for that tool.
9. If the tool needs a specific Python version, add:
   - `scripts\tool\python-version.txt` for folder tools
   - `scripts\tool.python-version.txt` for root tools
   The build uses the Windows `py` launcher with the version string (for example `3.11` or `3.11-64`).

## Build and install

From repo root:

```bat
tools\compile_all_apps.cmd -DryRun
tools\compile_all_apps.cmd
BUILD_AND_INSTALL.cmd
```

Build deps live in `requirements_py<major>.<minor>.txt` matching `.venv_py<major>.<minor>` (PyInstaller).
If you pin a tool to a specific Python version, install build deps from the matching file, for example:

```bat
py -3.11 -m pip install -r requirements_py3.11.txt
```

## Build environments

- Default: shared build env from `.venv_py<major>.<minor>`.
- Different Python version: shared per-version envs under `build\venv\py-<version>` reused across tools.
- If a tool's requirements install fails in a shared env, the build retries in an isolated env under `build\venv\isolated\`.

## Versioning and release notes

- Update `VERSION` for each release.
- Update per-tool versions in `scripts\<tool>\VERSION` when a tool changes.
- Add a brief summary to `RELEASE_NOTES.md`.
- Add per-tool notes to `scripts\<tool>\RELEASE_NOTES.md`.
- The bundle version is embedded into each EXE during build.

## Release checklist

1. `tools\compile_all_apps.cmd`
2. Verify `dist\` EXEs run (`ttree --version`, `wget --version`).
3. Create a git tag for the release.
4. Upload `dist\` EXEs to the release page (do not commit `dist`).
